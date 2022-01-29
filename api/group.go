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

package api

import (
	"context"
	"errors"
	"io/ioutil"
	"os"
	"os/exec"
	"time"

	"github.com/tetratelabs/run"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/dio/authservicebinary/generated/config"
	"github.com/dio/authservicebinary/internal/download"
	"github.com/dio/authservicebinary/internal/runner"
)

const (
	defaultBinaryVersion = "0.6.0-rc0"
	binaryHomeEnvKey     = "EXT_AUTH_SERVICE_HOME"
)

type Config struct {
	Version string
	// Location where the binary will be downloaded.
	Dir          string
	FilterConfig *config.Config
}

// New returns a new run.Service that wraps auth_server binary. Setting the cfg to nil, expecting
// setting the auth_server's --filter_config from a file.
func New(cfg *Config) *Service {
	if cfg == nil {
		cfg = &Config{} // TODO(dio): Have a way to generate default config.
	}
	return &Service{
		cfg: cfg,
	}
}

type Service struct {
	cfg           *Config
	cmd           *exec.Cmd
	binaryPath    string
	configPath    string
	filterCfgFile string
}

var _ run.Config = (*Service)(nil)

func (s *Service) Name() string {
	return "authservice"
}

func (s *Service) FlagSet() *run.FlagSet {
	flags := run.NewFlagSet("External AuthN/AuthZ Service options")
	flags.StringVar(
		&s.filterCfgFile,
		"external-auth-service-config",
		s.filterCfgFile,
		"Path to the filter config file")

	flags.StringVar(
		&s.cfg.Version,
		"external-auth-service-version",
		defaultBinaryVersion,
		"External auth server version")

	flags.StringVar(
		&s.cfg.Dir,
		"external-auth-service-directory",
		os.Getenv(binaryHomeEnvKey),
		"External auth server version")

	return flags
}

func (s *Service) Validate() error {
	if s.filterCfgFile != "" {
		b, err := os.ReadFile(s.filterCfgFile)
		if err != nil {
			return err
		}
		var cfg config.Config
		if err = protojson.Unmarshal(b, &cfg); err != nil {
			return err
		}
		s.cfg.FilterConfig = &cfg
	}

	if s.cfg.FilterConfig == nil {
		return errors.New("filter config is required")
	}
	return s.cfg.FilterConfig.ValidateAll()
}

func (s *Service) PreRun() (err error) {
	if s.cfg.Dir == "" {
		dir, err := ioutil.TempDir("", download.DefautBinaryName)
		if err != nil {
			return nil
		}
		s.cfg.Dir = dir
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Check and download the binary.
	s.binaryPath, err = download.VersionedBinary(ctx, s.cfg.Version, s.cfg.Dir, download.DefautBinaryName)
	if err != nil {
		return err
	}

	// Generate JSON config to run the auth_server. See: authservice/docs/README.md.
	jsonConfig, err := protojson.Marshal(s.cfg.FilterConfig)
	if err != nil {
		return err
	}

	tmp, err := ioutil.TempFile("", download.DefautBinaryName)
	if err != nil {
		return err
	}
	s.configPath = tmp.Name()

	if _, err = tmp.Write(jsonConfig); err != nil {
		return err
	}

	s.cmd = runner.MakeCmd(s.binaryPath, []string{"--filter_config", s.configPath}, os.Stdout)
	return nil
}

func (s *Service) Serve() error {
	// Run the downloaded auth_server with the generated config in s.configPath.
	_, err := runner.Run(s.cmd)
	return err
}

func (s *Service) GracefulStop() {
	if s.cmd != nil {
		s.cmd.Process.Signal(os.Interrupt)
	}
}
