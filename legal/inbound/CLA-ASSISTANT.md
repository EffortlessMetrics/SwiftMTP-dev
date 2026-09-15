# Hosted CLA Assistant governance

`EffortlessMetrics/SwiftMTP-dev` uses **CLA Assistant from `cla-assistant.io`**, the hosted GitHub App, for the [Individual Contributor License Agreement](CLA-INDIVIDUAL.md). It does not use CLA Assistant Lite or repository-hosted CLA workflow code.

## Activation state

This migration is staged until the hosted service is linked and proven on its pull request. Before merge, maintainers must create the public Gist from the reviewed ICLA and metadata payloads, install and link the hosted App, observe a successful `license/cla` status from that App, replace the pending Gist fields in [`CLA-ASSISTANT-SOURCE.json`](CLA-ASSISTANT-SOURCE.json), and require the status on the default branch with CLA Assistant pinned as its expected source.

## Agreement source

The App is linked to a public Gist containing `CLA.md` and `metadata`. The Gist `CLA.md` and repository [`CLA-INDIVIDUAL.md`](CLA-INDIVIDUAL.md) must be byte-identical. The staged custom-field payload is retained in [`CLA-ASSISTANT-METADATA.json`](CLA-ASSISTANT-METADATA.json). The activation state, exact Gist URL and revision, and content hashes are recorded in [`CLA-ASSISTANT-SOURCE.json`](CLA-ASSISTANT-SOURCE.json).

The required custom fields are full legal name, email address, and an acknowledgement that the signer is acting in an individual capacity and has authority to grant the stated rights.

## Corporate contributions and DCO

The hosted form is the individual flow. Corporate contributions remain governed by the separate [Entity Contributor License Agreement](CLA-ENTITY.md) and a maintainer-controlled authorization process. The repository's Developer Certificate of Origin sign-off remains required for commits; it is additional provenance evidence and does not replace either CLA.

## Enforcement

The migration pull request is the initial test pull request. It must first receive a successful `license/cla` status from the hosted App. The default-branch ruleset must then require that context and pin its expected source to CLA Assistant. The allowlist starts empty. A bot may be exempted only after its contribution path is shown to be controlled and attributable to the project.

## Evidence retention

Maintainers export the signature register privately when the ICLA changes and at release or governance-freeze checkpoints. The retained evidence set includes the exported register, Gist payload and revision, repository source record, ruleset JSON, and checksums. Personal signature data is not committed to this repository.

Changing the ICLA or `metadata` creates a new version. Update the repository and Gist in one governed change, update the source record, expect contributors to re-sign, and take a fresh private export.

See [`CLA-PRIVACY.md`](CLA-PRIVACY.md) for the contributor privacy notice.
