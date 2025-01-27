#!/bin/bash
echo "$(date): Script executed by process PID=$PPID"
kill -SIGTERM $PPID