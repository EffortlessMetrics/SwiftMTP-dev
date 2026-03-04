# Fish completion for swiftmtp
# Install: cp completions/swiftmtp.fish ~/.config/fish/completions/

# Disable file completions by default
complete -c swiftmtp -f

# Global options
complete -c swiftmtp -l real-only -d 'Only use real devices'
complete -c swiftmtp -l mock -d 'Use mock device'
complete -c swiftmtp -l mock-profile -d 'Mock profile to use' -xa 'pixel7 galaxy iphone canon default'
complete -c swiftmtp -l json -d 'Output as JSON'
complete -c swiftmtp -l jsonl -d 'Output as JSON Lines'
complete -c swiftmtp -l trace-usb -d 'Enable USB tracing'
complete -c swiftmtp -l trace-usb-details -d 'Enable detailed USB tracing'
complete -c swiftmtp -l strict -d 'Enable strict mode'
complete -c swiftmtp -l safe -d 'Enable safe mode'
complete -c swiftmtp -l vid -d 'Filter by vendor ID' -x
complete -c swiftmtp -l pid -d 'Filter by product ID' -x
complete -c swiftmtp -l bus -d 'Filter by USB bus' -x
complete -c swiftmtp -l address -d 'Filter by USB address' -x
complete -c swiftmtp -l help -d 'Show help'

# Subcommands (only when no subcommand given yet)
complete -c swiftmtp -n __fish_use_subcommand -a probe -d 'Discover connected MTP devices'
complete -c swiftmtp -n __fish_use_subcommand -a ls -d 'List device contents'
complete -c swiftmtp -n __fish_use_subcommand -a pull -d 'Download files from device'
complete -c swiftmtp -n __fish_use_subcommand -a push -d 'Upload files to device'
complete -c swiftmtp -n __fish_use_subcommand -a cp -d 'Copy objects on device (server-side)'
complete -c swiftmtp -n __fish_use_subcommand -a copy -d 'Copy objects on device (server-side)'
complete -c swiftmtp -n __fish_use_subcommand -a edit -d 'Edit files on Android devices'
complete -c swiftmtp -n __fish_use_subcommand -a delete -d 'Delete objects on device'
complete -c swiftmtp -n __fish_use_subcommand -a move -d 'Move objects on device'
complete -c swiftmtp -n __fish_use_subcommand -a thumb -d 'Download object thumbnails'
complete -c swiftmtp -n __fish_use_subcommand -a info -d 'Show detailed object/device info'
complete -c swiftmtp -n __fish_use_subcommand -a snapshot -d 'Create device snapshot'
complete -c swiftmtp -n __fish_use_subcommand -a mirror -d 'Mirror device content'
complete -c swiftmtp -n __fish_use_subcommand -a bench -d 'Benchmark transfers'
complete -c swiftmtp -n __fish_use_subcommand -a events -d 'Monitor device events'
complete -c swiftmtp -n __fish_use_subcommand -a quirks -d 'Show device quirks'
complete -c swiftmtp -n __fish_use_subcommand -a health -d 'Device health check'
complete -c swiftmtp -n __fish_use_subcommand -a storages -d 'List device storages'
complete -c swiftmtp -n __fish_use_subcommand -a collect -d 'Collect device diagnostics'
complete -c swiftmtp -n __fish_use_subcommand -a submit -d 'Submit device report'
complete -c swiftmtp -n __fish_use_subcommand -a add-device -d 'Add a new device profile'
complete -c swiftmtp -n __fish_use_subcommand -a wizard -d 'Interactive guided device setup'
complete -c swiftmtp -n __fish_use_subcommand -a device-lab -d 'Automated device testing matrix'
complete -c swiftmtp -n __fish_use_subcommand -a profile -d 'Device profile management'
complete -c swiftmtp -n __fish_use_subcommand -a diag -d 'Run diagnostics'
complete -c swiftmtp -n __fish_use_subcommand -a usb-dump -d 'Dump raw USB descriptors'
complete -c swiftmtp -n __fish_use_subcommand -a learn-promote -d 'Promote learned quirk to static'
complete -c swiftmtp -n __fish_use_subcommand -a bdd -d 'Run BDD scenarios'
complete -c swiftmtp -n __fish_use_subcommand -a storybook -d 'Run storybook demo'
complete -c swiftmtp -n __fish_use_subcommand -a version -d 'Show version information'

# Mirror subcommand options
complete -c swiftmtp -n '__fish_seen_subcommand_from mirror' -l dry-run -d 'Preview without changes'
complete -c swiftmtp -n '__fish_seen_subcommand_from mirror' -l delete -d 'Delete extraneous files'
complete -c swiftmtp -n '__fish_seen_subcommand_from mirror' -l format -d 'Filter by MTP format' -x
complete -c swiftmtp -n '__fish_seen_subcommand_from mirror' -l conflict -d 'Conflict resolution strategy' -xa 'newest largest source destination skip ask'

# File completions for commands that take paths
complete -c swiftmtp -n '__fish_seen_subcommand_from pull push ls delete move cp copy edit thumb info' -F
