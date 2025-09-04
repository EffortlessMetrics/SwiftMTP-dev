# Governance Policy

## Versioning

- **Semantic Versioning:** MAJOR.MINOR.PATCH
- **Breaking Changes:** Only in 2.0+ versions
- **Pre-release:** alpha, beta, rc suffixes for unstable versions

## Branches

- **main:** Always green, latest stable code
- **release/X.Y.x:** Patch branches for LTS releases
- **feature/***: Feature development (squash-merged)
- **fix/***: Bug fixes (squash-merged)

## Maintainers

Current maintainers:
- [List maintainer names and GitHub handles]

**Responsibilities:**
- Review PRs within 2 business days
- Ensure CI passes before merge
- Follow security disclosure process
- Maintain backwards compatibility

**Requirements:**
- Active contributor for 3+ months
- Demonstrated code quality and testing practices
- Commitment to project goals

## Pull Request Process

1. **Open PR:** Create descriptive PR with issue link
2. **CI Check:** Ensure all tests pass
3. **Review:** 1 maintainer + CI green = merge
4. **Merge:** Squash merge with conventional commit message

## Deprecation Policy

1. **Announcement:** Deprecate in release notes and code warnings
2. **Timeline:** Support deprecated features for 2 minor releases
3. **Removal:** Remove in next major version
4. **Migration Guide:** Provide clear migration path

## Backports

- **Security Fixes:** Backported to N-1 and N-2
- **Critical Bugs:** Backported to N-1 on case-by-case basis
- **Features:** Not backported, upgrade recommended

## Release Process

1. **Feature Freeze:** 2 weeks before release
2. **Release Candidate:** 1 week of testing
3. **Final Release:** Tag and publish
4. **Changelog:** Update with all changes

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Report issues to maintainers privately first
- No harassment or discriminatory behavior

---

**Last Updated:** [Date]
