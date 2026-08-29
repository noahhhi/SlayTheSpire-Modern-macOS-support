#!/bin/bash
# Preserve the wrapped installer's status without a trailing shell expression
# accidentally turning a successful PackageKit postinstall into a failure.
set -u

[ "$#" -gt 0 ] || {
  echo '[sts-modern] no installer command was supplied' >&2
  exit 2
}

INSTALL_RC=0
"$@" || INSTALL_RC=$?
exit "$INSTALL_RC"
