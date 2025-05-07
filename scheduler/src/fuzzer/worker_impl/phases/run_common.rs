use std::{sync::Arc, time::Instant};

use crate::{
    constants::EXECUTION_TIMEOUT_MULTIPLYER,
    fuzzer::{
        common::{common_calibrate, common_run, CalibrationError, ExecError, InputType},
        common_networked::networked_common_run,
        event_counter::FuzzerEventCounter,
        queue::QueueEntry,
        worker::FuzzingWorker,
        worker_impl::mutators,
    },
    sink::{self},
    sink_bitmap::BitmapStatus,
    source,
};
use anyhow::Result;
use fuzztruction_shared::util::DEBUG_CHECKS_ENABLED;
use nix::sys::signal::Signal;

use super::FuzzingPhase;

impl FuzzingWorker {
    /// Try to create a new [QueueEntry] from the current fuzzer configuration
    /// (sink input and mutation cache state). While this should be in most cases
    /// successfull, instability of the source or sink might cause this process to
    /// fail. However, this is not considered an error, and still yield Ok(())
    /// as return value.
    ///
    /// # Errors
    ///
    /// All errors returned by this function must be considered fatal.
    fn create_new_queue_entry(
        &mut self,
        bitmap_status: BitmapStatus,
        is_crash: bool,
    ) -> Result<Option<Arc<QueueEntry>>> {
        let worker_uid = self.uid();
        let entry = self.state.entry();
        let source = self.source.as_mut().unwrap();
        let sink = self.sink.as_mut().unwrap();
        let input = InputType::Parent(&entry);
        let mut virgin_map = sink.bitmap().clone_with_pattern(0xff);

        let calibration_result = common_calibrate(
            &self.config,
            source,
            sink,
            &input,
            Some(&mut virgin_map),
            Some(worker_uid),
            Some(self.state.phase()),
            Some(self.state.mutator()),
            Some(self.state.patch_point()),
            is_crash,
            Some(Arc::clone(&entry)),
        );

        match calibration_result {
            Ok(mut entry) => {
                if let BitmapStatus::NewEdge = bitmap_status {
                    // Mark the entry as favoured if it is covering a new edge.
                    entry.stats_rw().mark_favoured_once()
                }

                let mut queue = self.queue.lock().unwrap();
                entry.set_creation_ts((chrono::Utc::now() - queue.start_ts()).num_milliseconds());

                log::info!("New QueueEntry: {:#?}", &entry);
                let new_entry = queue.push(&entry);
                queue.print_queue_stats();
                drop(queue);

                let mut cerebrum_guard = self.cerebrum.write().unwrap();
                cerebrum_guard
                    .as_mut()
                    .unwrap()
                    .report_new_qe(Arc::clone(&new_entry));

                // Clear new bits from our local map.
                virgin_map.not();
                self.virgin_map.has_new_bit(&mut virgin_map);
                // Propagate cleared virgin bits to global map.
                let mut shared_virgin_map = self.shared_virgin_map.lock().unwrap();
                virgin_map.has_new_bit(&mut shared_virgin_map);
                drop(shared_virgin_map);

                return Ok(Some(new_entry));
            }
            Err(err) => match err.downcast_ref::<CalibrationError>() {
                Some(err) => {
                    // This is expected, just print the error and return.
                    log::info!("Queue entry calibration failed: {:?}", err);
                }
                None => {
                    log::error!("Unexpected error during calibration!");
                    return Err(err.context("Error while calibrating new queue entry"));
                }
            },
        }

        Ok(None)
    }

    /// Handle the case if the iteration failed before reaching the sink.
    #[inline]
    fn handle_source_exec_error(&mut self, stats: &mut FuzzerEventCounter, error: &ExecError) {
        match error {
            ExecError::SourceError(source_error) => match source_error {
                source::RunResult::TimedOut { .. } => {
                    stats.source_timeout += 1;
                }
                source::RunResult::Signalled { .. } => {
                    stats.source_crashes += 1;
                }
                r => {
                    unreachable!("Unexpected run result: {:?}", r);
                }
            },
            ExecError::NoSourceOutput => {
                stats.source_no_output += 1;
            }
            ExecError::DuplicatedOutput => {
                stats.source_duplicated_output += 1;
            }
        }
    }

    #[inline]
    fn handle_run_result_terminated(
        &mut self,
        stats: &mut FuzzerEventCounter,
        sink_input: &[u8],
    ) -> Result<()> {
        let sink = self.sink.as_mut().unwrap();
        let coverage_map = sink.bitmap();
        coverage_map.classify_counts();
        let current_hash32 = coverage_map.hash32();
        let edges_covered = coverage_map.count_bytes_set();

        self.check_if_nop_mutator_produced_different_coverage(current_hash32, edges_covered);

        let sink = self.sink.as_mut().unwrap();
        let coverage_map = sink.bitmap();
        let new_coverage = coverage_map.has_new_bit(&mut self.virgin_map);

        let bytes_set = coverage_map.count_bytes_set();
        if self.state.phase() == FuzzingPhase::Discovery
            && self.state.entry().covered_edges().count_bits_set() as f32 * 0.98_f32
                >= bytes_set as f32
        {
            return Ok(());
        }

        if matches!(new_coverage, BitmapStatus::NewEdge | BitmapStatus::NewHit) {
            // New coverage, consult global map.
            let mut global_virgin_map = self.shared_virgin_map.lock().unwrap();
            // Check whether this is globally a new path (and clear it from the global map).
            let has_new_bits = coverage_map.has_new_bit(&mut global_virgin_map);
            // Sync local map with global map, thus we do not need to grab the log next time
            // if we see an already seen path.
            self.virgin_map.copy_from(&global_virgin_map);
            drop(global_virgin_map);

            match has_new_bits {
                BitmapStatus::NewEdge => {
                    stats.edges_found += 1;
                }
                BitmapStatus::NewHit => {
                    stats.hits_found += 1;
                }
                BitmapStatus::NoChange => return Ok(()),
            }
            stats.last_finding_ts = Some(Instant::now());
            self.maybe_save_interesting_input(sink_input);
            self.create_new_queue_entry(has_new_bits, false)?;
        }

        Ok(())
    }

    fn check_if_nop_mutator_produced_different_coverage(
        &self,
        _current_hash32: u32,
        edges_covered: usize,
    ) {
        let is_nop_mutation = self.state.mutator() == mutators::MutatorType::Nop;
        if DEBUG_CHECKS_ENABLED && is_nop_mutation {
            let is_unstable = self.state.entry().sink_unstable();
            let _expected_hash32 = self.state.entry().bitmap_hash32();
            let expected_edges = self.state.entry().covered_edges().count_bits_set();

            let current_phase = self.state.phase();
            let last_mutator = self.state.last_mutator();

            if !is_unstable {
                let ratio = 1f64 - (edges_covered as f64 / expected_edges as f64);
                if ratio.abs() > 0.05 {
                    log::warn!("The queue entry {:?} covered an different number of edges (is {} but expected {}) than during its creation, eventhough it should be stable (phase is {}, mutator is {:?}).", self.state.entry().id(), edges_covered, expected_edges, current_phase, last_mutator);
                    // let entry = self.state.entry();
                    // let expected_bytes = entry.mutations();
                    // let mut mutations = self.source.as_ref().unwrap().mutation_cache().borrow().try_clone().unwrap();
                    // let current_bytes = unsafe { mutations.save_bytes() };
                } else {
                    log::trace!(
                        "The queue entry {:?} is stable (phase is {}).",
                        self.state.entry().id(),
                        current_phase
                    );
                }
            }
        }
    }

    fn handle_run_result_signalled(
        &mut self,
        stats: &mut FuzzerEventCounter,
        sink_input: &[u8],
        signal: Signal,
    ) -> Result<()> {
        let sink = self.sink.as_mut().unwrap();
        let coverage_map = sink.bitmap();
        let target_mutation_site = self.state.patch_point();
        coverage_map.classify_counts();

        let new_bits = FuzzingWorker::check_virgin_maps(
            coverage_map,
            &mut self.crash_virgin_map,
            &self.shared_crash_virgin_map,
        );

        match new_bits {
            BitmapStatus::NewEdge => {
                log::info!(
                    "Found new crash. signal={:?}, target_mutation_site={:?}",
                    signal,
                    target_mutation_site
                );
                stats.sink_unique_crashes += 1;
                stats.last_crash_ts = Some(Instant::now());
                let qe = self.create_new_queue_entry(new_bits, true)?;
                self.save_crashing_input_and_asan_ubsan_report(sink_input, signal, qe);
            }
            BitmapStatus::NewHit => {
                log::info!(
                    "Found new crash. signal={:?}, target_mutation_site={:?}",
                    signal,
                    target_mutation_site
                );
                stats.sink_unique_crashes += 1;
                stats.last_crash_ts = Some(Instant::now());
                let qe = self.create_new_queue_entry(new_bits, true)?;
                self.save_crashing_input_and_asan_ubsan_report(sink_input, signal, qe);
            }
            BitmapStatus::NoChange => (),
        }

        Ok(())
    }

    #[inline]
    fn handle_run_result(
        &mut self,
        stats: &mut FuzzerEventCounter,
        run_result: sink::RunResult,
        sink_input: &[u8],
    ) -> Result<()> {
        let _entry = self.state.entry();
        let sink = self.sink.as_mut().unwrap();
        let coverage_map = sink.bitmap();
        coverage_map.classify_counts();

        match run_result {
            sink::RunResult::Terminated(..) => {
                stats.successful_source_execs += 1;
                self.handle_run_result_terminated(stats, sink_input)?;
            }
            sink::RunResult::Signalled(signal) => {
                stats.sink_crashes += 1;
                self.handle_run_result_signalled(stats, sink_input, signal)?;
            }
            sink::RunResult::TimedOut => {
                stats.sink_timeout += 1;
                // if self.config.target_uses_network() {
                //     self.handle_run_result_terminated(stats, sink_input)?;
                // } else {
                //     stats.sink_timeout += 1;
                // }
            }
        }

        Ok(())
    }

    #[inline]
    pub fn do_run(
        &mut self,
        stats: &mut FuzzerEventCounter,
        input_bytes: &[u8],
        scratch_buffer: &mut Vec<u8>,
    ) -> Result<()> {
        let entry = self.state.entry();
        let source = self.source.as_mut().unwrap();
        let sink = self.sink.as_mut().unwrap();
        let timeout = entry
            .avg_exec_duration_raw()
            .mul_f64(EXECUTION_TIMEOUT_MULTIPLYER);

        let run_result = if self.config.target_uses_network() {
            networked_common_run(&self.config, source, sink, timeout)
        } else {
            common_run(
                &self.config,
                source,
                sink,
                input_bytes,
                timeout,
                scratch_buffer,
            )
        };

        match run_result {
            Ok(run_result) => {
                self.handle_run_result(stats, run_result, scratch_buffer)?;
            }
            Err(err) => {
                match err.downcast_ref::<ExecError>() {
                    Some(exec_error) => {
                        self.handle_source_exec_error(stats, exec_error);
                    }
                    None => {
                        // Unknown error => fatal
                        log::error!(
                            "Got unexpected error: {:#?}. child_exit_reason={:#?}",
                            err,
                            source.try_get_child_exit_reason()
                        );
                        return Err(err.context("Unexpected error while executing source/sink"));
                    }
                }
            }
        }

        Ok(())
    }
}
