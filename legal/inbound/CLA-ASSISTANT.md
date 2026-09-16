# Hosted CLA Assistant governance

`EffortlessMetrics/SwiftMTP-dev` uses **CLA Assistant from `cla-assistant.io`**, the hosted GitHub App, for the [Individual Contributor License Agreement](CLA-INDIVIDUAL.md). It does not use CLA Assistant Lite or repository-hosted CLA workflow code.

## Activation state

This migration is staged until the hosted service is linked and proven on its pull request. Before merge, maintainers must create the public Gist from the reviewed ICLA and metadata payloads, install and link the hosted App, observe a successful `license/cla` status from that App, replace the pending Gist fields in [`CLA-ASSISTANT-SOURCE.json`](CLA-ASSISTANT-SOURCE.json), and require the status on the default branch with CLA Assistant pinned as its expected source.

## Agreement source

The App is linked to a public Gist containing `CLA.md` and `metadata`. The Gist `CLA.md` and repository [`CLA-INDIVIDUAL.md`](CLA-INDIVIDUAL.md) must be byte-identical. The staged custom-field payload is retained in [`CLA-ASSISTANT-METADATA.json`](CLA-ASSISTANT-METADATA.json). The activation state, exact Gist URL and revision, and content hashes are recorded in [`CLA-ASSISTANT-SOURCE.json`](CLA-ASSISTANT-SOURCE.json).

The required custom fields are full legal name, email address, and an acknowledgement that the signer is acting in an individual capacity and has authority to grant the stated rights.

## Corporate contributions and DCO

The hosted form is the individual flow. Corporate contributions remain governed by the separate [Entity Contributor License Agreement](CLA-ENTITY.md) and a maintainer-controlled authorization process. The repository's Developer Certificate of Origin sign-off remains required for commits; it is additional provenance evidence and does not replace either CLA.

An entity-owned contribution does not create a false individual signature and does not put a human account or employer organization on the CLA Assistant allowlist. After an Entity CLA is executed, the private authorization record must identify the entity, agreement version, covered GitHub usernames, scope, and effective date.

The entity merge path is an audited exception to the CLA rule only:

1. enforce the App-pinned `license/cla` check in a dedicated default-branch CLA ruleset, separate from the repository's baseline branch ruleset;
2. make a dedicated `cla-corporate-approvers` team the only `pull_request`-mode bypass actor on that CLA-only ruleset;
3. require an approver to verify the private Entity CLA record before bypassing the CLA ruleset for a specific pull request; and
4. retain a private receipt containing the entity, agreement version, covered usernames, pull request, approver, timestamp, and reason.

All ordinary pull-request, review, CI, deletion, non-fast-forward, and DCO controls remain enforced. Until the Entity CLA and the narrowly scoped exception path are both configured, an entity-owned contribution cannot merge.

## Enforcement

The migration pull request is the initial test pull request. It must first receive a successful `license/cla` status from the hosted App. A dedicated default-branch CLA ruleset must then require that context and pin its expected source to CLA Assistant. Keep the existing baseline ruleset unchanged and without new bypass actors. The CLA-only ruleset starts with no bypass actor; add only the dedicated entity-approval team if the entity process described above is activated.

The CLA Assistant allowlist starts empty. A bot may be exempted only after its contribution path is shown to be controlled and attributable to the project. Do not use that allowlist for collaborators, organization members, or entity contributors.

## Evidence retention

Maintainers export the signature register privately when the ICLA changes and at release or governance-freeze checkpoints. The retained evidence set includes the exported register, Gist payload and revision, repository source record, ruleset JSON, and checksums. Personal signature data is not committed to this repository.

Changing the ICLA or `metadata` creates a new version. Update the repository and Gist in one governed change, update the source record, expect contributors to re-sign, and take a fresh private export.

See [`CLA-PRIVACY.md`](CLA-PRIVACY.md) for the contributor privacy notice.
