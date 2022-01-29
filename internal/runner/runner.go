// Copyright 2022 Dhi Aurrahman
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package runner

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"syscall"

	"github.com/dio/authservicebinary/internal/downloader"
)

func Run(cmd *exec.Cmd) (int, error) {
	err := cmd.Start()
	if err != nil {
		return 1, fmt.Errorf("failed to start %s: %w", downloader.DefautBinaryName, err)
	}

	// Buffered, since caught by sigchanyzer: misuse of unbuffered os.Signal channel as argument to
	// signal.Notify.
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		s := <-c
		_ = cmd.Process.Signal(s)
		// TODO(dio): Handle windows.
	}()

	err = cmd.Wait()
	if err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			waitStatus, _ := exitError.Sys().(syscall.WaitStatus)
			return waitStatus.ExitStatus(), nil
		}
		return 1, fmt.Errorf("failed to launch %s: %v", downloader.DefautArchivedBinaryName, err)
	}
	return 0, nil
}

func MakeCmd(binary string, args []string, out io.Writer) *exec.Cmd {
	cmd := exec.Command(binary, args...) //nolint:gosec
	cmd.Stdin = os.Stdin
	// TODO(dio): Kill all child processes.
	if out == nil {
		cmd.Stdout = os.Stdout
	} else {
		cmd.Stdout = out
	}
	cmd.Stderr = os.Stderr
	return cmd
}
