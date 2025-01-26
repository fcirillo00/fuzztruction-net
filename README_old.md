# Fuzztruction-Net
<p><a href="https://mschloegel.me/paper/bars2024fuzztructionnet.pdf"><img alt="Fuzztruction-Net Paper Thumbnail" align="right" width="320" src="https://github.com/user-attachments/assets/04904703-ded2-4a97-a185-6b35df84fe9e"></a></p>


Fuzztruction-Net is an academic prototype of a fuzzer that does not directly mutate the input messages (as most other fuzzers do) sent to network applications under test, but it uses a fundamentally different approach that relies on *fault injection* instead. Effectively, we inject faults to force one of the communication peers into a weird state where its output no longer matches the expectations of the target peer, thereby potentially uncovering bugs. Importantly, this *weird peer* can still properly encrypt/sign the protocol messages, overcoming a fundamental challenge of current network application fuzzing. This is because we leave the communication system intact but introduce small corruptions. Since we can turn both the server or the client into a weird peer, our approach is the first capable of testing client-side network applications effectively.

For more details, check out our [paper](https://mschloegel.me/paper/bars2024fuzztructionnet.pdf).
<!-- To cite our work, you can use the following BibTeX entry:
```bibtex
@inproceedings{bars2023fuzztruction,
  title={No Peer, No Cry: Network Application Fuzzing via Fault Injection},
  author={Bars, Nils and Schloegel, Moritz and Schiller, Nico and Bernhard, Lukas and Holz, Thorsten},
  booktitle = {ACM Conference on Computer and Communications Security (CCS)},
  year={2024},
}
``` -->

For instructions on how to reproduce the experiments from our paper, please read the [`fuzztruction-net-experiments`](https://github.com/fuzztruction/fuzztruction-net-experiments) submodule documentation *after* reading this document.

> <b><span style="color:red">Compatibility:</span></b> While we try to make sure that our prototype is as platform independent as possible, we are not able to test it on all platforms. If you run into issues, please use Ubuntu 22.04.2, which we used during development as the host system.





## Quickstart
```bash
# Clone the repository. This is required to be placed at your user's
# home directory, if you are planning to replicate our evaluation via the
# scripts provided in the fuzztruction-experiments submodule.
git clone https://github.com/fuzztruction/fuzztruction-net.git && \
    cd fuzztruction-net && \
    git submodule update --init

# Option 1: Get a pre-built version of our runtime environment.
# To ease reproduction of experiments in our paper, we recommend using our
# pre-built environment to avoid incompatibilities (~80 GB of data will be
# downloaded)
# Do NOT use this if you don't want to reproduce our results but instead fuzz
# own targets (use the next command instead).
./env/pull-prebuilt.sh

# Option 2: Build the runtime environment for Fuzztruction-Net from scratch.
# Do NOT run this if you executed pull-prebuilt.sh
./env/build.sh

# Spawn a container based on the image built/pulled before.
# To spawn a container using the prebuilt image (if pulled above),
# you need to set USE_PREBUILT to 1, e.g., `USE_PREBUILT=1 ./env/start.sh`
./env/start.sh

# Calling this script again will spawn a shell inside the container.
# (can be called multiple times to spawn multiple shells within the same
#  container).
./env/start.sh

# Runninge start.sh the second time will automatically build the fuzzer.

# See `Fuzzing a Target using Fuzztruction-Net` below for further instructions.
```

## Components
Fuzztruction-Net assumes two applications (called "peers") communicate via some network protocol. It will inject faults into one of the peers, called "weird peer", with the goal of fuzzing the second peer, called "target peer". To this end, Fuzztruction-Net contains the following core components:

### ****Scheduler****
The scheduler orchestrates the interaction of the weird peer and the target peer. It governs the fuzzing campaign, and its main task is to organize the fuzzing loop. In addition, it also maintains a queue containing queue entries. Each entry consists of the seed input passed to the weird peer (if any) and all mutations applied to the weird peer. Each such queue entry represents a single test case. In traditional fuzzing, such a test case would be represented as a single file. The implementation of the scheduler is located in the [`scheduler`](./scheduler/) directory.

### ****Weird Peer****
The weird peer can be considered a seed generator for producing inputs tailored to the fuzzing target, the target peer. Current network application fuzzers either replace the weird peer and send (mutated), pre-recorded messages to the target peer, or they mutate messages as a Man-in-the-Middle on the fly. Both types of approaches fall short in testing the target peer, as they are generally unaware of session state (they cannot reuse ephemeral values, e.g., session IDs), nor can they deal with encryption or other integrity protection mechanisms. By injecting faults into the weird peer, we overcome these challenges: The weird peer is an application that---by design---can correctly process and maintain session state, and it can apply all protection mechanisms; otherwise, it would not work as intended. Fault injection slightly subverts this correct behavior, causing erroneous and unexpected behavior in the target peer, thereby uncovering bugs. Note that it may happen that our faults corrupt the handling of session state or protection mechanisms, but this is no concern: It will cause an early termination of the communication, thus achieve less coverage, and thus the fault will be deprioritzed by our fuzzer and no longer scheduled.

The implementation of the weird peer can be found in the [`generator`](./generator/) directory. It consists of two components that are explained in the following.

#### ****Compiler Pass****
The compiler pass ([`generator/pass`](./generator/pass/)) instruments the target using so-called [patch points](https://llvm.org/docs/StackMaps.html). Since the current (tested on LLVM17.0.6 and below) implementation of this feature is unstable, we patch LLVM to enable them for our approach. The patches can be found in the [`llvm`](https://github.com/fuzztruction/fuzztruction-llvm) repository (included here as submodule). Please note that the patches are experimental and not intended for use in production.

The locations of the patch points are recorded in a separate section inside the compiled binary. The code related to parsing this section can be found at [`lib/llvm-stackmap-rs`](https://github.com/fuzztruction/llvm-stackmap-rs), which we also published on [crates.io](https://crates.io/crates/llvm_stackmap).

During fuzzing, the scheduler chooses a target from the set of patch points and passes its decision down to the agent (described below) responsible for applying the desired mutation for the given patch point.

#### **Agent**
The agent, implemented in [`generator/agent`](./generator/agent/) is running in the context of the weird peer that was compiled with the custom compiler pass. Its main tasks are the implementation of a forkserver and communicating with the scheduler. Based on the instruction passed from the scheduler via shared memory and a message queue, the agent uses a JIT engine to mutate the weird peer.

### ****Consumer****
The weird peer's counterpart is the target peer: It is the target we are interested in testing and the communication partner of the weird peer. For Fuzztruction-Net, it is sufficient to compile the target peer with the customized AFL++ compiler pass we ship in TODO, which we use to record the coverage feedback. This feedback guides our mutations of the weird peer.

# Preparing the Runtime Environment (Docker Image)
Before using Fuzztruction-Net, the runtime environment that comes as a Docker image is required. This image can be obtained by building it yourself locally or pulling a pre-built version. Both ways are described in the following. Before preparing the runtime environment, this repository, and all sub repositories, must be cloned:
```bash
git clone --recurse-submodules https://github.com/fuzztruction/fuzztruction-net.git
```

### ****Local Build****
The Fuzztruction-Net runtime environment can be built by executing [`env/build.sh`](./env/build.sh). This builds a Docker image containing a complete runtime environment for Fuzztruction-Net locally. By default, a [pre-built version](https://hub.docker.com/repository/docker/nbars/fuzztruction-llvm_debug) of our patched LLVM version is used and pulled from Docker Hub. If you want to use a locally built LLVM version, check the [`llvm`](https://github.com/fuzztruction/fuzztruction-llvm) directory.

### ****Pre-built****
In most cases, there is no particular reason for using the pre-built environment -- except if you want to reproduce the exact experiments conducted in the paper. The pre-built image provides everything, including the pre-built evaluation targets and all dependencies. The image can be retrieved by executing [`env/pull-prebuilt.sh`](./env/pull-prebuilt.sh).


The following section documents how to spawn a runtime environment based on either a locally built image or the prebuilt one. Details regarding the reproduction of the paper's experiments can be found in the [`fuzztruction-net-experiments`](https://github.com/fuzztruction/fuzztruction-net-experiments) submodule.


## Managing the Runtime Environment Lifecycle
After building or pulling a pre-built version of the runtime environment, the fuzzer is ready to use. The fuzzer's environment lifecycle is managed by a set of scripts located in the [`env`](./env/) folder.

| Script | Description |
|--|---|
| [`./env/start.sh`](./env/start.sh)  | Spawn a new container or spawn a shell into an already running container. <b><span style="color:red">Prebuilt:</span></b> Exporting `USE_PREBUILT=1` spawns a container based on a pre-built environment. For switching from pre-build to local build or the other way around, `stop.sh` must be executed first.  |
| [`./env/stop.sh`](./env/stop.sh)  | This stops the container. Remember to call this after rebuilding the image. Same as for the `start.sh` script, `USE_PREBUILT=1` must be set as environment variable if the prebuilt runtime environment is used.  |

Using [`start.sh`](./env/start.sh), an arbitrary number of shells can be spawned in the container. Using Visual Studio Codes' [Containers](https://code.visualstudio.com/docs/remote/containers) extension allows you to work conveniently inside the Docker container.

Several files/folders are mounted from the host into the container to facilitate data exchange. Details regarding the runtime environment are provided in the next section.


## Runtime Environment Details
This section details the runtime environment (Docker container) provided alongside Fuzztruction-Net. The user in the container is named `user` and has passwordless `sudo` access per default.

> <b><span style="color:red">Permissions:</span></b> The Docker images' user is named `user` and has the same User ID (UID) as the user who initially built the image. Thus, mounts from the host can be accessed inside the container. However, in the case of using the pre-built image, this might not be the case since the image was built on another machine. This must be considered when exchanging data with the host.

Inside the container, the following paths are (bind) mounted from the host:

| Container Path |  Host Path | Note  |
|:--|---|----|
| `/home/user/fuzztruction`  | `./`  |<b><span style="color:red">Pre-built:</span></b> This folder is part of the image in case the pre-built image is used. Thus, changes are not reflected to the host.  |
| `/home/user/shared`  | `./`  | Used to exchange data with the host. |
| `/home/user/.zshrc`  | `./data/zshrc`  | -  |
|  `/home/user/.zsh_history` | `./data/zsh_history`  | - |
|  `/home/user/.bash_history` |  `./data/bash_history` | - |
| `/home/user/.config/nvim/init.vim`  |  `./data/init.vim` | - |
| `/home/user/.config/Code`  | `./data/vscode-data`  | Used to persist Visual Studio Code config between container restarts. |
| `/ssh-agent`  | `$SSH_AUTH_SOCK`  | Allows using the SSH-Agent inside the container if it runs on the host.  |
| `/home/user/.gitconfig`  | `/home/$USER/.gitconfig`  | Use gitconfig from the host, if there is any config.  |
| `/ccache`  | `./data/ccache`  | Used to persist `ccache` cache between container restarts. |

# Usage
After building the Docker runtime environment and spawning a container, the Fuzztruction-Net binary itself must be built. After spawning a shell inside the container using [`./env/start.sh`](./env/start.sh), the build process is triggered automatically. Thus, the steps in the next section are primarily for those who want to rebuild Fuzztruction after applying modifications to the code.

## Building Fuzztruction-Net
For building Fuzztruction-Net, it is sufficient to call `cargo build` in `/home/user/fuzztruction`. This will build all components described in the [Components](#Components) section. The most interesting build artifacts are the following:


| Artifacts  |  Description  |
|--:|---|
|`./generator/pass/fuzztruction-source-llvm-pass.so` | The LLVM pass is used to insert the patch points into the weird peer. <b><span style="color:red">Note:</span></b> The location of the pass is recorded in `/etc/ld.so.conf.d/fuzztruction.conf`; thus, compilers are able to find the pass during compilation. If you run into trouble because the pass is not found, please run `sudo ldconfig` and retry using a freshly spawned shell.  |
| `./generator/pass/fuzztruction-source-clang-fast`  | A compiler wrapper for compiling the weird peer. This wrapper uses our custom compiler pass, links the targets against the agent, and injects a call to the agents' init method into the weird peer's main.  |
| `./target/debug/libgenerator_agent.so`  | The agent the is injected into the weird peer.  |
| `./target/debug/fuzztruction`  | The fuzztruction binary representing the actual fuzzer. |

## Fuzzing a Target using Fuzztruction-Net
We will use `dropbear` as an example to showcase Fuzztruction-Net's capabilities. Since `dropbear` is relatively small and has no external dependencies, it is not required to use the pre-built image for the following steps.

### **Building the Target**
 <b><span style="color:red">Pre-built: If the pre-built version is used, building is unnecessary and this step can be skipped.</span></b><br>
Switch into the `fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked` directory and execute `./build.sh libpng src deps generator consumer`. This will pull the source and start the build according to the steps defined in `libpng/config.sh`.

### **Benchmarking the Target**
Using the following command (see note regarding the choice between debug and release)
```bash
# If built with in debug mode (default)
sudo ./target/debug/fuzztruction ./fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked/dropbear/dbclient_dropbear.yml --purge --log-output benchmark -i 25
# If built in release mode or using the prebuilt image
sudo ./target/release/fuzztruction ./fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked/dropbear/dbclient_dropbear.yml --purge --log-output benchmark -i 25
```
allows testing whether the target works. Each target is defined using a `YAML` configuration file. The files are located in the `configurations/networked` directory and are a good starting point for building your own config. The `dbclient_dropbear.yml` file is extensively documented.

> [!NOTE]
> You need to choose one of debug or release (second component of the path), depending on the whether you passed `--release` to `cargo build` or not.
> If you are using the prebuilt image, this must be set to release.


### **Troubleshooting**
If the fuzzer terminates with an error, there are multiple ways to assist your debugging efforts.

- Passing `--log-output` to `fuzztruction` causes stdout/stderr of the weird peer and the target peer if they are not used for passing or reading data from each other to be written into files in the working directory.
- Setting AFL_DEBUG in the `env` section of the `sink` in the `YAML` config can give you a more detailed output regarding the target peer.
- Executing the weird peer and target peer using the same flags as in the config file might reveal any typo in the command line used to execute the application. In the case of using `LD_PRELOAD`, double check the provided paths.

### **Running the Fuzzer**
To start the fuzzing process, executing the following command is sufficient:
```bash
# For debug builds.
sudo ./target/debug/fuzztruction ./fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked/dropbear/dbclient_dropbear.yml fuzz -j 10 -t 10m
# For release builds or if using the prebuilt image.
sudo ./target/release/fuzztruction ./fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked/dropbear/dbclient_dropbear.yml fuzz -j 10 -t 10m
```
This will start a fuzzing run on 10 cores, with a timeout of 10 minutes. Output produced by the fuzzer is stored in the directory defined by the `work-directory` attribute in the target's config file. In case of `dropbear`, the default location is `/tmp/dclient-dropbear-1`.

If the working directory already exists, `--purge` must be passed as an argument to `fuzztruction` to allow it to rerun.

<!-- ### **Computing Coverage**
After the fuzzing run is terminated, the `llvm-cov` subcommand allows to compute coverage for a fuzzing run. -->
