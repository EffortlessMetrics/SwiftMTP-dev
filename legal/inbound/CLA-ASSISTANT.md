# Hosted CLA Assistant Operating Record

**Repository:** `EffortlessMetrics/SwiftMTP-dev`  
**Status:** Pending activation; this change must remain draft until the activation receipts below are complete.  
**Expected status context:** `license/cla`  
**Repository ICLA SHA-256:** `ca8f71e16c13c875a73a922f48422e5ca29d63a78a72d65d2d116f8c46f76e87`

## Decision

Use the hosted **CLA Assistant** GitHub App from `cla-assistant.io` for the [Individual Contributor License Agreement](CLA-INDIVIDUAL.md). Do not add a repository CLA workflow.

The app enforces SwiftMTP's ICLA; it does not supply the agreement. The ICLA already permits open-source and commercial relicensing. This migration changes the signing mechanism, not that grant.

The [Entity Contributor License Agreement](CLA-ENTITY.md) remains a separate written process. The [Developer Certificate of Origin](DCO.txt) sign-off remains required for commits and does not replace either CLA.

## Agreement source

CLA Assistant must present a public Gist whose contents are byte-equivalent to [CLA-INDIVIDUAL.md](CLA-INDIVIDUAL.md).

- **Gist URL:** `PENDING — record before merge`
- **Gist revision:** `PENDING — record before merge`
- **Gist content SHA-256:** `PENDING — must equal the repository ICLA SHA-256 above`

Changing the Gist creates a new ICLA version and requires individual contributors to sign that version. Update all three fields whenever the ICLA changes.

## Individual signing fields

Require only:

1. full legal name;
2. email address; and
3. acknowledgement: **I am signing in my individual capacity and have authority to grant the rights stated in this Agreement.**

GitHub identity and signature time come from the authenticated signing event.

Entity-owned Contributions stay outside this flow. An authorized signatory must complete the ECLA and the maintainers must retain the authorization record privately.

## Enforcement

1. Install the hosted CLA Assistant GitHub App on this repository only.
2. Start with no human, collaborator, or organization-member exemptions.
3. Add an automation account to the allowlist only when it actually authors project-controlled contributions and its provenance is documented.
4. Open a test pull request and verify both unsigned and signed behavior.
5. Confirm that the app emits `license/cla`.
6. Add `license/cla` to the `main` ruleset as a required status check.
7. Pin the required check to the CLA Assistant App as its expected source.
8. Record the test pull request and ruleset receipt below.

- **Activation test PR:** `PENDING`
- **Ruleset receipt:** `PENDING`
- **Expected-source receipt:** `PENDING`

## Evidence retention

Export the hosted individual signature register privately:

- whenever the ICLA or Gist revision changes;
- at release or governance freeze checkpoints; and
- before replacing or discontinuing the service.

Store exports outside the public repository with a checksum and the corresponding Gist revision. Keep entity agreements and authority records in the same private licensing archive. The hosted database must not be the sole licensing record.

Contributor data handling is described in [CONTRIBUTOR-PRIVACY.md](CONTRIBUTOR-PRIVACY.md).
