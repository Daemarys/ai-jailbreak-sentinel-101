# Contributing

Thanks for your interest in improving this project!

## How to Contribute

1. **Fork** the repository
2. **Create a branch** for your change (`git checkout -b feature/my-change`)
3. **Make your changes** and test them
4. **Submit a pull request** with a clear description

## What We're Looking For

- New jailbreak test cases (add to `tests/`)
- Additional KQL hunting queries (add to `hunting/`)
- Sentinel analytics rules for new attack patterns
- Documentation improvements
- Bug fixes

## Guidelines

- Test scripts must use `lab.config.ps1` for all Azure resource references — never hardcode tenant IDs, endpoints, or resource names
- All attack simulations must target only resources the user owns
- Keep PowerShell compatible with both 5.1 and 7+
- Update `TESTING.md` if you add new test scripts

## Security

If you discover a security vulnerability, please report it privately via GitHub Security Advisories rather than opening a public issue.
