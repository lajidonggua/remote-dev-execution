#!/bin/sh

# Print one file metadata value using the first stat implementation that exits
# successfully. Each probe is captured independently so stdout from a failed
# command can never leak into the accepted result.
rde_stat() {
  rde_stat_field=$1
  rde_stat_path=$2

  case $rde_stat_field in
    owner)
      rde_stat_bsd_format=%u
      rde_stat_gnu_format=%u
      ;;
    mode)
      rde_stat_bsd_format=%Lp
      rde_stat_gnu_format=%a
      ;;
    *)
      return 1
      ;;
  esac

  if rde_stat_value=$(stat -f "$rde_stat_bsd_format" "$rde_stat_path" 2>/dev/null); then
    printf '%s\n' "$rde_stat_value"
    return 0
  fi
  if rde_stat_value=$(stat -c "$rde_stat_gnu_format" "$rde_stat_path" 2>/dev/null); then
    printf '%s\n' "$rde_stat_value"
    return 0
  fi
  return 1
}
