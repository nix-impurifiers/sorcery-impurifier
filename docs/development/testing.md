# Testing

Run `nix flake check -L`. The QEMU fixture runs the pinned upstream native Sorcery
installer, cast/dispel and real CastFS through Linux FUSE. Assert native installed
state and file inventories as well as application behavior: native exit status
alone is insufficient. Preserve upstream licenses and disclose compatibility
patches. Cover failure/retry, offline import, native configuration policy,
accounts/permissions, roots, host-library updates and garbage collection.
