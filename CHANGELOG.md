# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### ✨ New features

- _...Add new stuff here..._

### 🐞 Bug fixes

- _...Add new stuff here..._

### 🧩 Architectural changes

- _...Add new stuff here..._

## [1.1.0] - 2026-08-06

### 🐞 Bug fixes

- Corrected address validation guidance to use the asynchronous Jobs API (`StartJob` with Action `ValidateAddress`, plus `GetJob`/`ListJobs`/`CancelJob`) instead of Geocode. Rewrote the Address Verification reference, relabeled the Geocode step in the Address Input reference as address-to-coordinates resolution (not validation), and updated the core API selection guidance so geocoding is no longer conflated with address validation.

## [1.0.0] - 2025-02-25

### ✨ New features

- Initial release to provide curated AI Agent context as:
  - [Kiro power](https://kiro.dev/powers/)
  - Claude Code and Cursor [plugin](https://github.com/awslabs/agent-plugins/tree/main/plugins/amazon-location-service)
  - [Agent Skills](https://agentskills.io/home) format skill
  - Direct context files
- Progressive disclosure with additional context entries:
  - Address Input
  - Address Verification
  - Calculate Routes
  - Dynamic Map
  - Places Search
  - Web JavaScript SDK
