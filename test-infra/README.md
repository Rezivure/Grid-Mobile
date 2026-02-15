# Grid E2E Test Infrastructure

Self-contained test environment with a local Matrix (Synapse) server, test accounts, and Maestro UI flows.

## Prerequisites

- Docker Desktop
- Maestro CLI (`curl -Ls "https://get.maestro.mobile.dev" | bash`)
- Java (Temurin JDK)
- iOS Simulator with Grid installed (`flutter run` first)

## Quick Start

```bash
# 1. Start infrastructure (Synapse + create 13 test accounts)
cd test-infra
docker compose up -d --wait

# 2. Run Maestro tests
cd ..
maestro test .maestro/

# 3. Tear down
cd test-infra
docker compose down -v
```

## Or use the all-in-one script:

```bash
cd test-infra
./scripts/run-tests.sh          # Full run, tears down after
./scripts/run-tests.sh --keep   # Keep infra running after tests
./scripts/run-tests.sh --no-maestro  # Just start infra
```

## Test Accounts

| Username | Password | Role |
|----------|----------|------|
| admin | adminpass123 | Admin |
| testuser1-12 | testpass123 | User |

Server: `http://localhost:8008`

## Maestro Flows

| Flow | Description |
|------|-------------|
| 01_app_launches | Welcome screen renders correctly |
| 02_onboarding_flow | Get Started → signup screen |
| 03_custom_provider_flow | Custom Server login form |
| 04_login_local_server | Full login against local Synapse |

## GPX Location Mocks

Feed fake GPS to the simulator:
```bash
xcrun simctl location booted set 40.7128,-74.0060          # Static point
xcrun simctl location booted simulate-route test-infra/gpx/nyc-walk.gpx  # Moving
```

## Architecture

```
test-infra/
├── docker-compose.yml      # Synapse + account setup
├── synapse/
│   ├── homeserver.yaml     # Synapse config (open reg, no rate limits)
│   └── log.config          # Minimal logging
├── scripts/
│   ├── setup-accounts.sh   # Creates 13 test accounts via admin API
│   └── run-tests.sh        # All-in-one test runner
├── gpx/
│   └── nyc-walk.gpx        # Simulated walk: Times Square → Central Park
└── README.md
```
