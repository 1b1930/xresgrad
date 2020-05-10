#!/bin/sh

PROGRESS_CURR=0
PROGRESS_TOTAL=7679                        

# This file was autowritten by rmlint
# rmlint was executed from: /home/daniel/project/python/xresgrad/v2/
# Your command line was: rmlint /mnt/hdd

RMLINT_BINARY="/usr/bin/rmlint"

# Only use sudo if we're not root yet:
# (See: https://github.com/sahib/rmlint/issues/27://github.com/sahib/rmlint/issues/271)
SUDO_COMMAND="sudo"
if [ "$(id -u)" -eq "0" ]
then
  SUDO_COMMAND=""
fi

USER='daniel'
GROUP='daniel'

STAMPFILE=$(mktemp 'rmlint.XXXXXXXX.stamp')

# Set to true on -n
DO_DRY_RUN=

# Set to true on -p
DO_PARANOID_CHECK=

# Set to true on -r
DO_CLONE_READONLY=

# Set to true on -q
DO_SHOW_PROGRESS=true

# Set to true on -c
DO_DELETE_EMPTY_DIRS=

# Set to true on -k
DO_KEEP_DIR_TIMESTAMPS=

##################################
# GENERAL LINT HANDLER FUNCTIONS #
##################################

COL_RED='[0;31m'
COL_BLUE='[1;34m'
COL_GREEN='[0;32m'
COL_YELLOW='[0;33m'
COL_RESET='[0m'

print_progress_prefix() {
    if [ -n "$DO_SHOW_PROGRESS" ]; then
        PROGRESS_PERC=0
        if [ $((PROGRESS_TOTAL)) -gt 0 ]; then
            PROGRESS_PERC=$((PROGRESS_CURR * 100 / PROGRESS_TOTAL))
        fi
        printf '%s[%3d%%]%s ' "${COL_BLUE}" "$PROGRESS_PERC" "${COL_RESET}"
        if [ $# -eq "1" ]; then
            PROGRESS_CURR=$((PROGRESS_CURR+$1))
        else
            PROGRESS_CURR=$((PROGRESS_CURR+1))
        fi
    fi
}

handle_emptyfile() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty file:${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_emptydir() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty directory: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rmdir "$1"
    fi
}

handle_bad_symlink() {
    print_progress_prefix
    echo "${COL_GREEN} Deleting symlink pointing nowhere: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_unstripped_binary() {
    print_progress_prefix
    echo "${COL_GREEN} Stripping debug symbols of: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        strip -s "$1"
    fi
}

handle_bad_user_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER" "$1"
    fi
}

handle_bad_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chgrp ${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chgrp "$GROUP" "$1"
    fi
}

handle_bad_user_and_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}:${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER:$GROUP" "$1"
    fi
}

###############################
# DUPLICATE HANDLER FUNCTIONS #
###############################

check_for_equality() {
    if [ -f "$1" ]; then
        # Use the more lightweight builtin `cmp` for regular files:
        cmp -s "$1" "$2"
        echo $?
    else
        # Fallback to `rmlint --equal` for directories:
        "$RMLINT_BINARY" -p --equal  --no-followlinks "$1" "$2"
        echo $?
    fi
}

original_check() {
    if [ ! -e "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    if [ ! -e "$1" ]; then
        echo "${COL_RED}^^^^^^ Error: duplicate has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    # Check they are not the exact same file (hardlinks allowed):
    if [ "$1" = "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original and duplicate point to the *same* path - cancelling.....{COL_RESET}"
        return 1
    fi

    # Do double-check if requested:
    if [ -z "$DO_PARANOID_CHECK" ]; then
        return 0
    else
        if [ "$(check_for_equality "$1" "$2")" -ne "0" ]; then
            echo "${COL_RED}^^^^^^ Error: files no longer identical - cancelling.....${COL_RESET}"
        fi
    fi
}

cp_symlink() {
    print_progress_prefix
    echo "${COL_YELLOW}Symlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with symlink
            rm -rf "$1"
            ln -s "$2" "$1"
            # make the symlink's mtime the same as the original
            touch -mr "$2" -h "$1"
        fi
    fi
}

cp_hardlink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't hardlink so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    echo "${COL_YELLOW}Hardlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with hardlink
            rm -rf "$1"
            ln "$2" "$1"
        fi
    fi
}

cp_reflink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't clone so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    # reflink $1 to $2's data, preserving $1's  mtime
    echo "${COL_YELLOW}Reflinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            touch -mr "$1" "$0"
            if [ -d "$1" ]; then
                rm -rf "$1"
            fi
            cp --archive --reflink=always "$2" "$1"
            touch -mr "$0" "$1"
        fi
    fi
}

clone() {
    print_progress_prefix
    # clone $1 from $2's data
    # note: no original_check() call because rmlint --dedupe takes care of this
    echo "${COL_YELLOW}Cloning to: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        if [ -n "$DO_CLONE_READONLY" ]; then
            $SUDO_COMMAND $RMLINT_BINARY --dedupe  --dedupe-readonly "$2" "$1"
        else
            $RMLINT_BINARY --dedupe  "$2" "$1"
        fi
    fi
}

skip_hardlink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already hardlinked to original): ${COL_RESET}$1"
}

skip_reflink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already reflinked to original): ${COL_RESET}$1"
}

user_command() {
    print_progress_prefix

    echo "${COL_YELLOW}Executing user command: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        # You can define this function to do what you want:
        echo 'no user command defined.'
    fi
}

remove_cmd() {
    print_progress_prefix
    echo "${COL_YELLOW}Deleting: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            if [ ! -z "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                touch -r "$(dirname $1)" "$STAMPFILE"
            fi

            rm -rf "$1"

            if [ ! -z "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                # Swap back old directory timestamp:
                touch -r "$STAMPFILE" "$(dirname $1)"
                rm "$STAMPFILE"
            fi

            if [ ! -z "$DO_DELETE_EMPTY_DIRS" ]; then
                DIR=$(dirname "$1")
                while [ ! "$(ls -A "$DIR")" ]; do
                    print_progress_prefix 0
                    echo "${COL_GREEN}Deleting resulting empty dir: ${COL_RESET}$DIR"
                    rmdir "$DIR"
                    DIR=$(dirname "$DIR")
                done
            fi
        fi
    fi
}

original_cmd() {
    print_progress_prefix
    echo "${COL_GREEN}Keeping:  ${COL_RESET}$1"
}

##################
# OPTION PARSING #
##################

ask() {
    cat << EOF

This script will delete certain files rmlint found.
It is highly advisable to view the script first!

Rmlint was executed in the following way:

   $ rmlint /mnt/hdd

Execute this script with -d to disable this informational message.
Type any string to continue; CTRL-C, Enter or CTRL-D to abort immediately
EOF
    read -r eof_check
    if [ -z "$eof_check" ]
    then
        # Count Ctrl-D and Enter as aborted too.
        echo "${COL_RED}Aborted on behalf of the user.${COL_RESET}"
        exit 1;
    fi
}

usage() {
    cat << EOF
usage: $0 OPTIONS

OPTIONS:

  -h   Show this message.
  -d   Do not ask before running.
  -x   Keep rmlint.sh; do not autodelete it.
  -p   Recheck that files are still identical before removing duplicates.
  -r   Allow deduplication of files on read-only btrfs snapshots. (requires sudo)
  -n   Do not perform any modifications, just print what would be done. (implies -d and -x)
  -c   Clean up empty directories while deleting duplicates.
  -q   Do not show progress.
  -k   Keep the timestamp of directories when removing duplicates.
EOF
}

DO_REMOVE=
DO_ASK=

while getopts "dhxnrpqck" OPTION
do
  case $OPTION in
     h)
       usage
       exit 0
       ;;
     d)
       DO_ASK=false
       ;;
     x)
       DO_REMOVE=false
       ;;
     n)
       DO_DRY_RUN=true
       DO_REMOVE=false
       DO_ASK=false
       ;;
     r)
       DO_CLONE_READONLY=true
       ;;
     p)
       DO_PARANOID_CHECK=true
       ;;
     c)
       DO_DELETE_EMPTY_DIRS=true
       ;;
     q)
       DO_SHOW_PROGRESS=
       ;;
     k)
       DO_KEEP_DIR_TIMESTAMPS=true
       ;;
     *)
       usage
       exit 1
  esac
done

if [ -z $DO_REMOVE ]
then
    echo "#${COL_YELLOW} ///${COL_RESET}This script will be deleted after it runs${COL_YELLOW}///${COL_RESET}"
fi

if [ -z $DO_ASK ]
then
  usage
  ask
fi

if [ ! -z $DO_DRY_RUN  ]
then
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
    echo "#${COL_YELLOW} /// ${COL_RESET} This is only a dry run; nothing will be modified! ${COL_YELLOW}///${COL_RESET}"
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
fi

######### START OF AUTOGENERATED OUTPUT #########

handle_emptydir '/mnt/hdd/dl/ps2bios' # empty folder
handle_emptyfile '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.glo' # empty file
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Env_ScavengerBirds_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Movers/BIOA_zCHR10_APL_MOV_zTurnTable_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA30/BIOA_sta_30_escape_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_non_council_races_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/DSG/BIOA_UNC10_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Smoke_Prototype.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_PREFAB_TEST.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Squad_Formation.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_03_X_Morningafter_M_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/Bioa_PRC2_ccspace_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_non_sapient_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/DSG/BIOA_UNC10_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_OmniBall_Prototype.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_War30_Respawn.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO_20_E_Asari_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA30/BIOA_STA_30_Departure_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCThai.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_extinct_species_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/BIOA_UNC10_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_portalTest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_War_MZhou.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_AdditionalContent.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_03_X_Finale_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END20_02_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_non_council_races_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/CIN/BIOA_UNC10_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Grenade_02_WallMine.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_ProFlyBy.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOA_APL_DOR_NOR10Door01_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_03_X_Morningafter_F_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END20_Bridge_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_council_races_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/BIOA_UNC13.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Grenade_03_Shrapnel.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_War30_02_Death.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Credits.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO20/BIOA_PRO_20_D_Beacon_2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/ART/BIOA_END80_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_extinct_species_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/BIOA_UNC13_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Explosion_PrototypeTest_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Blast_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Test.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_03_X_Final_Asari_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END20_02_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/cha00_player_walla_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/SND/BIOA_UNC11_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/gameplay_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Grenade_01_Stun.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Explosion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_CharacterRecord.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_H_Spectre_2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/ART/BIOA_END20_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_council_races_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/SND/BIOA_UNC11_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_TropicalWater.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Deaths_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOG_APL_DOR_REFVehDoor_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_I_Spectre_4_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/ART/BIOA_END70_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/17 - The Secret Labs.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/cha00_humanmale_kaidan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/LAY/BIOA_UNC11_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Explosion_Prototype_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Explosions.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ROM_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_F_Ashley_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/BIOA_END00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/18 - The Alien Queen.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/cha00_player_walla_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/SND/BIOA_UNC11_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_RainDrops.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_BloodGib.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE00_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_Pro_10_G_Spectre_1_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/BIOA_END00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/15 - The Thorian.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS50/los50_conduit_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/LAY/BIOA_UNC11_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/EA_HELP_HU.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_Snow.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_CombatBoost_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA_30_Departure_Fast_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_A_Flyby4_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/CRD/DSG/BIOA_CRD00_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/16 - Noveria.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/cha00_humanmale_kaidan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/LAY/BIOA_UNC11_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_PollenSeeds.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Adrenaline_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_GLO_00_A_Opening_FlyBy_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_D_Ambush_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/CRD/DSG/BIOA_CRD00_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/13 - Feros.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS50/los50_conduit_crash_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/DSG/BIOA_UNC11_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_Rain.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Blood_Creature.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Conversation.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_CBT_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/CRD/BIOA_CRD00.sfm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/14 - Protecting The Colony.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS50/los50_conduit_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/LAY/BIOA_UNC11_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_CalestonAir.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_AsteroidBelt.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_ConversationWheel.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_GTH_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/CRD/BIOA_CRD00_LOC_int.sfm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/11 - Liara'"'"'s World.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_ambient_02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/DSG/BIOA_UNC11_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Env_Dust_fall.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_Powers_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_END40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_AnimTree_Weapon.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/EntryMenu.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/12 - A Very Dangerous Place.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_ash_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/DSG/BIOA_UNC11_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_computer_female_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_DEATHVFX.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Rover.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_CAM_FX_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/EntryMenu_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/09 - Criminal Elements.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_ambient_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/DSG/BIOA_UNC11_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_computer_female_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_DMGTYPES.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Message.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_AnimTree_Creatures.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/testterrain.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/10 - Spectre Induction.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_ambient_02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/DSG/BIOA_UNC11_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_batarian_lieutenant_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_UNC80_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.ews' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO00_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_AnimTree_Humanoid.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/entry.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/07 - The Presidium.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_weapons_armor_combat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/BIOA_UNC11_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_batarian_lieutenant_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_WAR20_T_ST02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_WAR00_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR50/BIOA_WAR_50_G_Timber_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70D_Bridge_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/08 - The Wards.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_ambient_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/CIN/BIOA_UNC11_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_batarian_leader_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_NOR10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/DLC_UNC.dat' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_Placeables_CoverHeights01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_AMB_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70D_Bridge_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/06 - The Citadel.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_technology_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/CIN/BIOA_UNC17_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_batarian_leader_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/DLC_Vegas.dat' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Loot.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR30/BIOA_WAR_30_H_respawn_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70C_Bridge_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/xenia_master.zip' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_weapons_armor_combat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/DSG/BIOA_UNC17_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/Soundsets/dlc_geth_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_mud_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/HtmlHelp.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_AreaMap.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR40/BIOA_WAR_40_R_treachery_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70C_Bridge_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Burnout Revenge [NTSCU].iso' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_ships_vehicles_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/BIOA_UNC17.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/DLC_UNC_GlobalTlk.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/runme.dat' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambsecurity_female01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR30/BIOA_WAR_30_A_reveal_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02E_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_technology_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/BIOA_UNC17_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_weap_tracer_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Shockwave_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambsecurity_male01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR30/BIOA_WAR_30_G_Death_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02E_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/33 - Final Assault.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_planets_locations_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/SND/BIOA_UNC13_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/Soundsets/batarian_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Stun_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG40_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_male03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR20/BIOA_WAR_20_Y_FlyBy2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02C_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/34 - Victory.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_ships_vehicles_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/SND/BIOA_UNC13_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_weap_impact_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Impacts.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambsecurity_female01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR20/BIOA_WAR_20_Z_Departure_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02C_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/31 - In Pursuit Of Saren.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_humanity_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/LAY/BIOA_UNC13_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_weap_infrared_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_MAIN_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_male02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR20/BIOA_WAR_20_A_FlyBy_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02BSuicide_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/32 - Infusion.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_planets_locations_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/SND/BIOA_UNC13_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_veh_physMat_test.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Stone_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_15_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_male03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR20/BIOA_WAR_20_M_Zhou_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02BSuicide_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/29 - Uplink.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_citadel_government_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/LAY/BIOA_UNC13_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_weap_casings_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Wood_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_16_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_male01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCave_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02BNode_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/30 - Battling Saren.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_humanity_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/LAY/BIOA_UNC13_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_trevs_waterfall.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Sand_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_13_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_male02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCrate_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02BNode_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/27 - Vigil.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_doctor_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/DSG/BIOA_UNC13_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_trevsAuroraBorealis.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_14_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_female02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/SND/BIOA_UNC52_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02BDeath_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/28 - Sovereign'"'"'s Theme.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_engineer_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/LAY/BIOA_UNC13_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Plastic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_male01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAhern_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02BDeath_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/25 - Uncharted Worlds.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_cutscene_oculon_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/DSG/BIOA_UNC13_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Robot_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_female01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/SND/BIOA_UNC52_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END20_Bridge_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/26 - Ilos.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_doctor_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/DSG/BIOA_UNC13_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Grass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_female02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/SND/BIOA_UNC52_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END70_02A_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/23 - Exit.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_comm_room_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/CIN/BIOA_UNC13_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Metal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambmilitia_male02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/SND/BIOA_UNC52_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAirlock_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/24 - Love Theme.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_cutscene_oculon_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC13/DSG/BIOA_UNC13_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_contact_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambrefugee_female01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/SND/BIOA_UNC52_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAirlock_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/21 - Breeding Ground.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_comm_room2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/DSG/BIOA_UNC20_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_contact_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_dMetal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambmilitia_male01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccahern_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/22 - Virmire Ride.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_comm_room_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/DSG/BIOA_UNC20_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_console_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Toxic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambmilitia_male02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/SND/BIOA_UNC52_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAirlock.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/19 - Fatal Confrontation.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_char_creation_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/DSG/BIOA_UNC20_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_console_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_DARKE_Death.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_trig_deadguys_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAhern_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/20 - Saren'"'"'s Base.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_comm_room2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/DSG/BIOA_UNC20_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_diary_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Ion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAhern_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_trig_deadguys.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_captain_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/CIN/BIOA_UNC20_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_diary_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Phasic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_radiochatter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_char_creation_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/DSG/BIOA_UNC20_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_cutscene_first_batarian_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Generic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_trig_deadguys_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCAhern.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_juliannabaynham.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_backgrounds_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/BIOA_UNC20_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/EA_HELP_IT.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_cutscene_first_batarian_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Xmod_Geth_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG70_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_juliannabaynham_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_11_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_radiochatter.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_captain_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/BIOA_UNC21_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_cutscene_discovered_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Corrosive_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_14_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_radiochatter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/LAY/BIOA_UNC52_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_11_DSG_LOC_IT.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_gunman.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_ash_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/SND/BIOA_UNC17_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_cutscene_discovered_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_EMP_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/BIOA_LAV00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_heajeong_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EngineFonts.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_11_DSG_LOC_DE.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_heajeong.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_backgrounds_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/BIOA_UNC20.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_computer_warnings_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Tracers_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_juliannabaynham_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EngineResources.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_11_DSG_LOC_FR.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambsecurity_male02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_choice_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/LAY/BIOA_UNC17_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_computer_warnings_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Weapons_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_13_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_gunman_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_ASA_ARM_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04b_DSG_LOC_IT.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_kaidan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/SND/BIOA_UNC17_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_PRCTYPES.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Muzzles_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_heajeong_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EditorResources.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambsecurity_female01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_ash_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/LAY/BIOA_UNC17_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_DLC_APL_PHY_Human_Lamp.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Powers_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/BIOA_PRC2AA.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04b_DSG_LOC_FR.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambsecurity_male01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_choice_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/LAY/BIOA_UNC17_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/Batarian/BIOG_BAT_HED_PROMorph_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ImpCrust_Ion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_gunman_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/bioa_prc2aa_00_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04b_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambrefugee_male02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/DSG/BIOA_UNC17_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_TNL_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ImpCrust_Plasma_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambsecurity_male02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCThai_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLava.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambrefugee_male03.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_ash_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC17/DSG/BIOA_UNC17_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/BIOG_CBT_DCB_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Impacts_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/CombatPerfTest.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLava_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambrefugee_female02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sovereign_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/BIOG_CBT_DGH_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ImpCrust_HighExplosive_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambsecurity_male01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim04_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCrate_L.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambrefugee_male01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_trig_main_facility_radio_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_DiscoBall_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambsecurity_male02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim05_dsg_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccrate_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambmilitia_male02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless04_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_trig_main_facility_radio_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Fire_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_vi_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim02_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccrate02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambrefugee_female01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sovereign_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_trig_batarians_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Blossoms_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_CHARALL_MASTER_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim03_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCrate_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_batarian_leader.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_trig_batarians_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Butterflys_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccscoreboard_dsg_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCrate.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_batarian_lieutenant.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless04_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_surveyor_wrapup_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Bar_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_vi_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim01_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccrate01_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/dlc_geth.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_surveyor_wrapup_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Bar_Znelson.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG80_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_lizbeth_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLava_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCave_L.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/dlc_plottest_test.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_surveyor_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env__WATER__Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMain_Conv.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccave_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/batarian.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_surveyor_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_AshCloud.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_krogan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_A_NodeClose_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccave04_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/codex_dlc.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_radio_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Geth_EyeLens_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_lizbeth_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_F_OCInterior_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCave_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/x06_garrus_final.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_cutscene_escape_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_radio_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Powers_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_joker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END_70_B_Relay_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccave02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/x06_player_final.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_party_comment1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Muzzle_Cannon_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Cin_spaceRailAmbient.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_krogan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END80/BIOA_END_80_B_Control_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccave03_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_vi.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_VehicleBooster_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Death_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_claw01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/Conversations/BIOG_HMM_CC_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCCave.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/wrex.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_cutscene_escape_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Reproducci_n_autom_tica_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ZombieAttack.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_67_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_joker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END70_SarenDeathFinal_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cccave01_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_lizbeth.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_asariscientist_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Water_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ZombieGib.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/PlotManagerAuto.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMid.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA30_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Lava_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_DARKE_Imp_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_claw01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/v_AndrewsExplosionofAwesomeness.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid01_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_joker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV60/lav60_trig02_base_fallback_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/La_instalaci_n_se_bloquea_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Mud_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_Disintegrate.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG_V_Env_Sanstorm.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMain_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_krogan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_asariscientist_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_DustTracks.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC21.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR50/war50_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/EffectsLensFlares.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMain_TXT.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Inicio_Del_Juego.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Dust_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC24.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_RAD_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG_GesturesConfig.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cclobby_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war50_claw01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV60/lav60_trig02_base_fallback_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Instalaci_n_Del_Juego.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Decal_Dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC17.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_SAR_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG_MORPH_FACE.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMain_Conv_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc_music_test.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_saren_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA70_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Decal_Snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC20.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_QEN_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG__EnvFX__.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLobby_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/snd_prc1_cin_pack.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC11_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/BIOA_LAV00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_RAC_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG_ForceFeedback.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLobby_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_trig_batarians.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_sal_ostern_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA70_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Damage_Lv3_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC13.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV60_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_GTR_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EngineScenes.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cclobby02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_trig_main_facility_radio.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_saren_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA70_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Stone_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC11.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_14_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_MAW_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BioEditorMaterials.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLobby_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_surveyor.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_kaidan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/EA_HELP_FI.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Wood_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC11_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG20_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Copy of bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_CBG_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_RoverLand_X06_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cclobby01_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_surveyor_wrapup.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG80/jug80_sal_ostern_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Sand_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapTER20_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_GSP_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE20/BIOA_ICE_20_A_FlyByC_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cclobby02_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_human_prisoner02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_door00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC10.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_AMB_MON_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_RoverDrop_X06_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLobby.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_human_radio.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_door01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_JUG_20_FlyBy_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA70.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_AMB_MUS_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_RoverLand_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cclobby01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_human_contact.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_JUG_70_Mexec_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapTER20.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/content_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_AMB_GAS_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_03_explosion_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCLava_L.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_human_prisoner01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_door00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_ICE_60_Regicide_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA60_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn5_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_AMB_KEE_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_RoverDrop_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_cclava_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_diary.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig04_elevator_ride_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_ICE_60_Tartovsky_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA60_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn6_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_AMB_BUG_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_01_Lucan_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim01_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_human_console.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA60_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_END_20_Relay_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA30_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn5_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_AMB_COW_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_01_Relay_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim02_dsg_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_cutscene_discovered.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig03_krogan_boss_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA70_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_END_80_C_Uplink_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA60_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn5_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Female_Player_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_OpeningSEQ08_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCSim.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_cutscene_first_batarian.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig04_elevator_ride_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA70_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_CIN_SpaceBattles2_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC82.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn4_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Male_Player_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_B_SovereignEXT_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim01_dsg_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_computer_female.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig02_mining_laser_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA60_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_Tracers_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC83.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn5_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_calanthablake_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_OpeningSEQ03_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccscoreboard_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/prc1_computer_warnings.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig03_krogan_boss_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA60_11_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_LOS_40.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC80.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn4_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_davinandersson_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_openingSEQ05_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccscoreboard_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig01_attention_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_Sovereign_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC81.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn4_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_G_SarenDead_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMid_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig02_mining_laser_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA60_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_Explosion01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC71.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn3_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_calanthablake_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/end90_crd_non-speaking_facefx.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/01 - Mass Effect Theme.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_party_comment2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_08_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_fExplosion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC73.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG80_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn4_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_badraltalaqani_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_F_OCInteriorSHT1_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid04_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_trig01_attention_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_DistressCall_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC61.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn3_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_F_OCInteriorSHT2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCMid_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_party_comment1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_07_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOG_V_Cin_END_SpaceScene.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC62.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn3_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_arceliasilvamartinez_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR30_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid03_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LAV70/lav70_party_comment2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Z_MATERIALS_A_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC54.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn2_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_badraltalaqani_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid04_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_wise_turian.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_armature_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Z_MESHES_A_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC55.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn3_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientsniper01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR30_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/snd_prc2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_bc_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_ShieldImpact.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC51.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn2_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_arceliasilvamartinez_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR30_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid03_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_krogan_frat_boy.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_a_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_War30_02_Reveal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC53.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn2_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientmain03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid01_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_ochren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_armature_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA30_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_PRO10_05_AshleyIntro.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC31.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/minimize_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientsniper01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccmid02_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_guard_number_two.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_security_system_start_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_ProBeaconAtk_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC42.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/mute_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientmain02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShadowDepthVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_jealous_jerk.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_a_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/PLC/BIOA_STA20_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_MeshTracer_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC25.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/close_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientmain03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShadowProjectionCommon.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_ahern.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_security_system_done_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA70_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_Nuke_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC30.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/minimize_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientmain01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShaderComplexityApplyPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/ISACT/prc2_bryant.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_security_system_start_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/BIOA_UNC10.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_JUG80_Nukeversion.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR40_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn8_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientmain02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShadowDepthPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/snd_prc1_music.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_armatures_active_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA60_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_CIN_KeeperBlood.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR40_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/close_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_machadoyle_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ScreenVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/ISACT/snd_prc_fusion_torch.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_security_system_done_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA60_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_Enlightenment.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR40_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG20_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn8_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_mayoconnell_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShaderComplexityAccumulatePixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_turianguard.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_turret_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_CIN_Glass.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR40_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG40_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn8_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_inoste_merchant_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/PositionOnlyDepthVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_wrex_at_fists.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_armatures_active_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_END_80_B_Control.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR30_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG20_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn7_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_machadoyle_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ScreenPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_doran_reacts.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_door03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/EA_HELP_Fr.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_End_SarenDead_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR30_05.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG20_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn8_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_iannewstead_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/PointLightPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_gangmember.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_turret_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_UNC11_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR30_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn7_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_inoste_merchant_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/PointLightVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_ai_conv3.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_door01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_DustNRocks.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR30_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn7_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_hollisblake_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ParticleTrailVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_choras.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS10/los10_trig_door03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_LOS_10_Landing_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR20_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn6_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_iannewstead_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ParticleVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_ai_conv1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_garrus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOA_V_CIN_STA_20_A_Arrival_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR30_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn7_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_hanamurakami_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ParticleSpriteVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_ai_conv2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_kaidan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_B_TK_Bomb.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR20_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn6_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_hollisblake_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ParticleSubUVVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_01_rita_complains.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_ashley_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_B_TK_Charge.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR20_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_00_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn6_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_gretaandersson_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ParticleBeamTrailVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_trig_02_jennas_contact.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_garrus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_AndrewsPortalTest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC92.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_14_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_hanamurakami_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ParticleBeamVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_schells.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_aaateam2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA20_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_B_TK_Aura.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC93.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_16_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_faizhou_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/TerrainVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_septimus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_ashley_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/SND/BIOA_STA30_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Andrews_Waterfall.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC84.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_gretaandersson_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/TextureDensityShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_rita.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_aaateam1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_AndrewsGeyserTest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapUNC90.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_davinandersson_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpotLightVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_scenicview.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_aaateam2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/ICE_DISINTEGRATE.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_JUG_20_A_Flyby_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_faizhou_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/TerrainDecalVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_quarian_cutscene.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_trig03_mira_tram_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/ScalingTrick.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LAV_20_A_FlyBy_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_05_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpeedTreeVertexFactoryBase.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_recruit01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_aaateam1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Smoke3D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ICE_20_A_FlyBy_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_valves_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpotLightPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/tali.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_tartakovsky_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05women_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_sparksTrial_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_WAR_20_A_FlyBy_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_04_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpeedTreeLeafCardVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/unc_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_trig03_mira_tram_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05women_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Proto__HologramNew_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOG_PHY_Weapons_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/News/en/register_en.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_05_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpeedTreeLeafMeshVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta90_council_spectre_start.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_mira_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Error_Message/_Program_has_caused_an_error__or__Error_in__gamename_.exe_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Proto__Render-2-Texture_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_GLO_00_B_Sovereign_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG70_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/webhelp.cab' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpeedTreeBillboardVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta90_grounded.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_tartakovsky_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Error_Message/Start_Error.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Proto__Holo3d_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOG_PHY_Creatures_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/News/en/btn_web_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_04_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR40_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SpeedTreeBranchVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta90_council_saren_start.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_ambient_alarm_loop3_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Error_Message/_Cannot_locate_CD_DVD-ROM_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Proto__Hologram_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOG_PHY_Humanoid_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/News/en/btn_web_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/CIN/BIOA_UNC52_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SimpleElementPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta90_council_spectre_induction.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_mira_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Error_Message/_CD_DVD_Emulation_Software_Detected_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_Andrews_FlashBangTest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOG_PHM_Characters_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/muted_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SimpleElementVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta90_captain.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_sal_comstore_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Direct_X/DirectX_Version_Does_not_Update_After_Installation.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_PowerUp_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOG_PHM_General_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/News/en/btn_web_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/BIOA_UNC52_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShadowVolumeVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta90_council_saren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_trig_wrex_killed_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Direct_X/Start_Direct_X.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_basic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOA_JUG80_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/mute_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/CIN/BIOA_UNC52_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/SimpleElementHitProxyPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_kahoku.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_sal_captainkirrahe_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Direct_X/_Direct3D__or__D3D__Errors.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Physics/BIOG_Humanoid_F.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/SND/BIOA_JUG20_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/muted_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethdrone_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_15_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShadowProjectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_tig_kahoku.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_sal_comstore_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Direct_X/_GET_SETUP__Error_When_Installing_DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR50_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_13_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethrcoming_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/BIOA_UNC52.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ShadowProjectionVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_escape.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_tali_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_03quarian_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Crash/Crashing_After_the_Splash_Screen.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_standard_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR50_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_14_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_command_post_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_13_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/eHelp.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_garrus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_sal_captainkirrahe_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_03quarian_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Crash/Start_Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_hot_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR40_05.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_gethdrone_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_14_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whproj.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_stgop3_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_09casino_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Controller/Start_Controller_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_mud_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapWAR50_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_12_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_mayoconnell_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/masseffectconfig.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_captain.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_tali_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_09casino_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Crash/Crashing_After_a_Full_Black_Screen.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE20_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_command_post_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/MassEffectLauncher.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_amb_diplomats.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_stgop2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_09A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_tw.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_goo_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE20_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambmilitia_female01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/click.wav' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta70_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_stgop3_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_09A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whtdhtml.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_WeaponsScope.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE20_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambmilitia_male01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/background.wma' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_iannewstead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_stgop1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08nodest_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_plist.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Decal_blood_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE20_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/default_ns.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR30/war30_trig_01_entry_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/VSMModProjectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_inoste_merchant.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_stgop2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_tbars.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_Stunned.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapFRE34.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR40/war40_ambmilitia_female01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/VSMProjectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_hanamurakami.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_liara_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whfts.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_T_TechMode.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapFRE35.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/PLC/BIOA_JUG80_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR30/war30_thorianasari_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/VSMDepthGatherVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_hollisblake.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_stgop1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whfwdata0.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_RenderStyle.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapFRE32.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR30/war30_trig_01_entry_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR50_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/VSMFilterDepthGatherPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_faizhou.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_kaidan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Sound/Start_Sound.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_Romance.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapFRE33.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR30/war30_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/VelocityShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_gretaandersson.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_amb_liara_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whftdata0.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_MotionBlur.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapFRE10.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR30/war30_thorianasari_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/VSMDepthGatherPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_calanthablake.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_asa_compalethea_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Lock-up_and_Freeze/Start_Locking_up_and_Freezing.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_PlayerDamage.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapFRE31.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/UberPostProcessBlendPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_davinandersson.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_asa_indoctrinat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Online_Connectivity_and_Performance/Start_Online_Connectivity_and_Performance.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Concrete_Pipe_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapEND80_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR30/war30_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/UberPostProcessBlendPixelShaderNoFilter.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_badraltalaqani.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_07toss_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Lock-up_and_Freeze/Locking_up_with_a_Repeating_Sound.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Cont_Tank_01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapEND80_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/default.css' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_wrongway2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/TranslucencyPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_asa_compalethea_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_07toss_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Lock-up_and_Freeze/Random_or_General_Lockups.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Anti_P_Mine.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapEND70.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/TranslucencyVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_ambientmain02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_kirrahe_checksin_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_07A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Install/Transfer_or_File_Error_During_Installation.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Cargo_Container_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapEND80_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_wrongway1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04b_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_arceliasilvamartinez.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_07A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Install/Virus_Warning_During_Installation.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_AlarmSensor01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SniperScope.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_wrongway2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04b_DSG_LOC_DE.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_ambientbunker02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_captainupdate_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02captain_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Install/INST_Start_Installation_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Anthid_Lodge_Collision.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapEND20.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_valves_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00torch_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/BIOG_UIWorld.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_ambientcommand01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_kirrahe_checksin_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02captain_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Install/Pre-Installation_Preparation.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_GUI_Hologram_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG70_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_trig_wrongway1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/DSG/BIOA_UNC73_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/varren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Install/4_Digit_Error_Code.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_MatFX_ICE.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG70_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC50/sp119_female_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00survey_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whtoc.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_ambientbunker01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_captainupdate_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Install/Autoplay_Screen_Does_not_Appear.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_water_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG20.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC51/sp110_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00torch_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/News/en/news.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambmilitia_female01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_wrex_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Getting_More_Help_Online/Start_Getting_More_Help_Online.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_GUI_Characters.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG40.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC50/sp110_researcher_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00main_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whidx.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war40_ambmilitia_male01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG40/jug40_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Graphics/Start_Graphics_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_sand_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE60_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_16_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC50/sp119_female_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00survey_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whtdata0.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war30_thorianasari.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_01A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Reinstalling_DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE60_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC50/sp110_distress_call_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00east_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whglo.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war30_trig_01_entry.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_wrex_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_01A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/UO_Trace.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_moss_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE60_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC50/sp110_researcher_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Maps/UNC52/DSG/BIOA_UNC52_00main_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whidata0.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_trig_wrex_killed_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Lowering_Sound_Acceleration.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_mud_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE60_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC42/sp126_darius_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whfts.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war30_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG20/jug20_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Preparing_your_Hard_Drive_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_grass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_06.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC50/sp110_distress_call_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whfwdata0.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_wrongway1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_fanatic02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_11news_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Ending_Background_Tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_leaf_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_07.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp120_standoff_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whst_topics.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_wrongway2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_mindless01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Finding_the_Minimum_System_Requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Sludge_Canister.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC42/sp126_darius_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whxdata/whftdata0.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_gethrcoming_04.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_fanatic01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_11A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Controller_Calibration.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_ThorianAcidSack.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_05.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp114_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whres.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_valves.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_fanatic02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_11news_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Emptying_your_Temp_Folder.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_MilitaryMaps.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_14_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp120_standoff_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_ep_ins.xml' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_gethrcoming_02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sal_psyrana_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Changing_Desktop_Resolution.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Rachni_Egg_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_14_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp114_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DepthOfFieldPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_gethrcoming_03.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_slv_fanatic01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_11A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Configuring_Routers_and_Firewalls.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_MedDiag_Equip.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE25.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp114_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DepthOfFieldVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_gethdrone.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sal_prisoner_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whtoc.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Medical_Bed_Scan.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapICE50_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_13_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp104_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/Definitions.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_trig_gethrcoming_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sal_psyrana_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/CD_DVD-ROM_Troubleshooting_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Harvester_Egg_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS30_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp114_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DepthOfFieldCommon.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_machadoyle.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sal_comperator_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whidx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Malfunction_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS30_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC55/sp115_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ColorPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/war20_mayoconnell.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sal_prisoner_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whtdata0.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_GethBattlePlatform.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS10_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_09_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC60/sp116_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/Common.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_trig_03_flagship.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_kro_docdroyas_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whglo.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_GethForceField.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS30.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC53/sp121_trig01_mine_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BranchingPCFModProjectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_trig_ai_machine.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_sal_comperator_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whidata0.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Generator.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLAV70_05.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC55/sp115_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BranchingPCFProjectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_trig_01_xeltancomplains.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Generator_Explosion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS10_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG80_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC53/sp121_mastermind_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BloomBlendVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_trig_02_lovescompanion.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_kro_docdroyas_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Fire_Ext_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLAV70_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC53/sp121_trig01_mine_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BranchingPCFCommon.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_terra_firma.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_asa_indoctrinat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_GDrone.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLAV70_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_male_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BasePassVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_trig04_remember_me.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/JUG70/jug70_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/LAY/BIOA_STA20_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Demo_Warhead_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLAV70_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC53/sp121_mastermind_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BloomBlendPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_reporter.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_julethventralis_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02side_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/El_juego_no_se_inicia_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Exp_FuelTank_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLAV70_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_male2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_17_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/PlotManagerDLC_Vegas.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_samesh.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_maintenance_door1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02side_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/El_juego_se_bloquea.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Plastic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG80_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_male_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/BasePassPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_negotiator.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_hanolar_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02ground_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Robot_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLAV60.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_major_kyle_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_15_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/PlotManagerDLC_UNC.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_receptionist.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_julethventralis_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02ground_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/EA_HELP_SP.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Moss_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG80_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_male2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_16_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/BIOC_BaseDLC_Vegas.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_human_ambassador_enter.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_curepuzzle_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02council_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Mud_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG80_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_female2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FilterPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_male_diplomat.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_hanolar_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA70_02council_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Leaf_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG70_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_major_kyle_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_14_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FilterVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_garrus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_checkpoint_guard_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10udina_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Metal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapJUG70_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC51/sp110_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/EmissivePixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_hanar_religious.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_curepuzzle_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10udina_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Grass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA30.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC52/sp119_female2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/EmissiveVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_family_argue.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_sick_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10E_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/CD_DVD_(Errores).htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Lava_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA30_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC82/sp122_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DOFAndBloomGatherPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_female_diplomat.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_checkpoint_guard_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10E_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/CD_DVD_(Errores)2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_UW_Weather01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA20.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC84/sp102_data_module_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DOFAndBloomGatherVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_requisition_officer.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_sick_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10D_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Whitepages/Updating_Drivers.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSTA20_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG40_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC82/sp122_distress_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DOFAndBloomBlendPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_snap_inspection.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_sick_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10D_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_Omni_Tool_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapPRO02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC82/sp122_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DOFAndBloomBlendVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_normandy_mechanic.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_4_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10C_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_Sabotage_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapSCI10.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG20_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC80/sp103_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DistortApplyScreenPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_officer_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_sick_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10C_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_DampingField_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapNOR03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_15_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC82/sp122_distress_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR50_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DistortApplyScreenVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_khalisah.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_4_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_EMP_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapPRO01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_16_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC72/sp117_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DistortAccumulatePixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_krogan_cutscene.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta00_popup_text_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Transmitter_Explosion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapNOR01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC80/sp103_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DistortAccumulateVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_girard.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_rachniqueen_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_TransTower_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapNOR02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_14_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC61/sp123_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DirectionalLightPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_jahleed.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_talinsomaai_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_LeavesFalling_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapMIN03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC72/sp117_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DirectionalLightVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_quarantine_guard_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_09A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Lightning.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapMIN10.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC61/sp119_gate_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR30_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DepthOnlyPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_chellik.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_rachniqueen_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Lav_DrillLaser.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS50_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn1_o.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC61/sp123_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR40_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/DepthOnlyVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_zabaleta.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_petozi_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_LavaSplash.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS50_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn2_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC61/sp107_datalog_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR30_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LDRTranslucencyCombinePixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_quarantine_guard_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_09A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_WaveCrash_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS40_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn1_h.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC61/sp119_gate_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR30_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LDRTranslucencyCombineVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_volus_ambassador.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_palon_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_03A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_lakeSteam.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Maps/MapLOS40_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn1_n.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC60/sp116_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_08_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HitProxyPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_xeltan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_petozi_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_RainInDistance.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOA_NOR_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/background.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC61/sp107_datalog_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HitProxyVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_trig_fan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_medbot_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_WaterFall_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOA_STA_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/data/launcher/btn1_d.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientcommand02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HeightFogPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_turian_religious.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_palon_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_03A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_GroundSmog_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOA_JUG00_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/rld.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientmain01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HeightFogVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_matriarch_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_02B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Hologram_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOA_LOS_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Splash/Splash.bmp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientcommand01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/GpuSkinVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_medbot_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_02B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Glass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_protheanPyramid.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientcommand02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HeightFogCommon.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_assassin_ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_maintenance_door2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_02A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_GroundFog_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Vehicles/BIOG_APL_VEH_GethShip.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/LAY/BIOA_JUG70_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientbunker03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/GammaCorrectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_assassins_dispatched.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_matriarch_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_02A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Fountain_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Geth_Pile_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientcommand01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR20_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/GammaCorrectionVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_market_buyer.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_maintenance_door1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_GethDrop_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_large_beacon_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientbunker02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_NOR10_03_GM_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FogVolumeCommon.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_market_conversation.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_maintenance_door2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Fish_01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Corpse_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientbunker03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/SND/BIOA_WAR20_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FoliageVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_flux_patron01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig08_tram_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Forcefield_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Frieghter_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientbunker01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_16_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FogVolumeApplyPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_flux_patron02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig09_assault_complete_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_ShipTakeoff_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_ConcreteBlock_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientbunker02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_17_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FogVolumeApplyVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_choras_patron02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig07_guard_rant_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_00news_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_SmokeBurning.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_ConcreteSlab_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war00_joker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_14_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FogIntegralPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_flux_customers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig08_tram_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_00news_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Rain_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Workbench.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war20_ambientbunker01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_15_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/FogIntegralVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_choras_cops.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig06_science_joke_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Rubble_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Frieghter.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC84/sp102_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_12_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/OcclusionQueryVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_amb_choras_patron01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig07_guard_rant_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_PollenSeeds_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_END20_APL_PLO_END20_RR_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/WAR20/war00_joker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_13_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/OneColorShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_trig_here2see_chellick.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig05_talin_frets_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Rain.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOG_APL_PLT_REFDesMarker01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC84/sp102_data_module_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/NullPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_wrex.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig06_science_joke_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_particleSmoke.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_GethGunship.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG_80_X_Outrun_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC84/sp102_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/OcclusionQueryPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_talitha.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig04_lab_ambush_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_PeakDrift.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_HeroBullet.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG_80_X_Outrun_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ModShadowVolumeVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta30_trig_01_jahleedfears.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig05_talin_frets_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_ENV_NOR_IceDecal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_World_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG80_13_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_captain_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/MotionBlurShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_post_harkin.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig02_noneshallpass_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_07A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/EA_HELP_UK.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_NorthernLights_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOA_PRO20_Train.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG80_13_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ModShadowProjectionVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_quarian.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig04_lab_ambush_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_07A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_NOR_EmssiveFX.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_NormandyAirlock_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG80_07_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ModShadowVolumePixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_jax.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig01_aggressivearrival_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_06news_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whgdef.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_NOR_ENGINEERING.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_UNC_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG80_07_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_traffic_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ModShadowCommon.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_jenna.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig02_noneshallpass_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whgdhtml.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Mist.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_FuncShots.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/PLC/BIOA_WAR50_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/ModShadowProjectionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_garrus_doctor.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_talinsomaai_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whfform.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_NEON_SIGNS_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_MEPC_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_traffic2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LocalVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_harkin.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig01_aggressivearrival_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_06news_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whgbody.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_meteorDrizzle.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_ElevatorBanter_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_traffic_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/MaterialTemplate.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_fists_guards02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_ambient_alarm_loop2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_05a_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whfbody.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_meteorShower.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_END80_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_diplomats_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LightFunctionVertexShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_friendly_security.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_ambient_alarm_loop3_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_03A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whfdhtml.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_Sun01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_DesignUNC_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_traffic2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LocalDecalVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_fist.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_ambient_alarm_loop1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support_rhc.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_Tornado_01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_DesignUtility_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_1liner_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LensFlareVertexFactory.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_fists_guards01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_ambient_alarm_loop2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_05a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_SnowDrifts_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_DesignerCombat_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_diplomats_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/LightFunctionPixelShader.usf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_doran.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig14_tram_controls_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_04A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/cshdat_robohelp.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_SteamPools_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_DesignLightChar_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sp101_garoth_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whutils.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_expat.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE70/ice70_ambient_alarm_loop1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA30_04A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_SandDrifts_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/Bioa_WAR_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_amb_1liner_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whver.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_chorban.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig13_thru_labs_peace_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_SandInAir.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Sequences/BIOG_ActionStations_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_wrex_at_fists_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whthost.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_doctor_michel.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig14_tram_controls_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_03A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_LightsBlinking.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Journal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sp101_garoth_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whtopic.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_banter_02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig12_olar_execution_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_02b_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_UW_Sand_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_LoadSave.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_saren_start_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whstub.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta60_black_market.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig13_thru_labs_peace_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_02rail_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Steam_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Honors.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_spectre_induction_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whtbar.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp122_distress.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig11_lab_sealed_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_02a_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Steam_Z_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Inventory.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_saren_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02I_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whproxy.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp122_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig12_olar_execution_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_02b_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_SovreignBastOff.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_GalaxyMap.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_saren_start_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02I_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whstart.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp121_mastermind.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig10_lab_exit_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_pdhtml.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_STA_Holograms.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_GameOver.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG20_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_captain_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02H_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whphost.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp121_trig01_mine.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig11_lab_sealed_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_02a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_pickup.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Snow_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Codex.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_saren_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02H_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whproj.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp120_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig09_assault_complete_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01scenic_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_mbars.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_SnowStorm_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_DesignerUI.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_tig_kahoku_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whmozemu.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp121_hackett.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_trig10_lab_exit_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01scenic_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_papplet.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_smokePlume_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/D3DCursors.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_captain_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whmsg.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig02_elevator_warn_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01nodest_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_homepage.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Snow_Ground_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_AdditionalContent.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_kahoku_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whihost.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp120_standoff.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig03_sentry_face_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01nodest_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_info.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_BioticMode.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/BIOG_GUI.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_tig_kahoku_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whlang.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_male.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig01_krogan_sniper_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01destiny_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_frmset01.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_BloodDrips.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/BIOG_GUI_Fonts_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_garrus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whghost.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_male2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig02_elevator_warn_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01destiny_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_frmset010.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_05_Stasis.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_TRN_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_kahoku_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whhost.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_gate.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_mira_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_blank.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_06_Weaken.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/Ships_Rough/Ships.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_escape_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_major_kyle.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig01_krogan_sniper_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA60_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_ep_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_03_Warp.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_HumanFreighter.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_garrus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_female.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_amb_announcements_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whproj.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_04_Barrier.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_ROV_Cinematic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_captain_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp119_female2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_mira_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whskin_banner.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_01_Throw.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_WindowPop.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA70/sta70_escape_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp117_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig09_assassin_enc_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whiform.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_B_02_Lift.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Journal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp105_mariedurand_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/RoboHHRE.lng' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp118_distress_call.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_amb_announcements_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whnjs.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_WaterFall_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Store.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp106_trig01_supplies_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_hanar_religious.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig07_aagun_warn_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whibody.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Welding_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_TeamSelect.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp105_amb_enlisted_male_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40V_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whtoc.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_negotiator.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig09_assassin_enc_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whidhtml.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_WarCloth.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Specialization.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp105_mariedurand_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40V_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.lng' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_crimeboss.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig06_gunship_warn_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_ENV_waterDrops_Z_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Splash.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG40_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp105_amb_enlisted_female_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_09_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whidx.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_family_argue.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig07_aagun_warn_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_VolumeLights_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Settings.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_15_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp105_amb_enlisted_male_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR40_10_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whtdata.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp_news_vids.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig05_chilly_krogan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_War_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_SkillGame.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_15_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC20/sp100_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whglo.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_companions_chatter.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig06_gunship_warn_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_VehDrop_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_RecordScreen.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_14_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp105_amb_enlisted_female_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whidata.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp126_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig15_krogan_decon_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA20_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Vehicles_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_ReplayCharacterSelect.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_14_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC20/sp100_on_the_move_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_16_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whfwdata.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp_follower_interject.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig19_rachni_encounter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA30_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/gameplay_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_Fusion_Death_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_ME_HUD.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC20/sp100_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_17_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whgdata.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp125_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig13_salarian_suicide_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/BIOA_STA00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_Ice_Death.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_MiniGameHanoi.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_grounded_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_14_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whftdata.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp126_darius.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig15_krogan_decon_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/BIOA_STA00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_TeslaIon_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_MainWheel.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC20/sp100_on_the_move_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_15_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whdata/whfts.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp125_amb_crazy.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig10_mira_bsod_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_Fire_Death.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Map.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_11_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_spectre_start_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/readme_en.txt' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp125_amb_crazyfemale.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig13_salarian_suicide_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/EA_HELP_DA.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_HighExplosive_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_Loot.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_grounded_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_13_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOC_Base.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp124_shadow_broker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig09_coolant_clue_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA60_08A_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Plasma_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_MainMenu.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_spectre_induction_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/MassEffect_101_en.txt' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp125_amb_bioticleader.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig10_mira_bsod_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Cryo_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_ST_Basic_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA90/sta90_council_spectre_start_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/MassEffect_102_en.txt' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp123_kahoku.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig06_mira_welcome_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA30_Departure_Fast_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XMod_Fusion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_WAR50_CSO.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp104_logs_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.syn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp123_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig09_coolant_clue_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA60_08A_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Weap__Trcr_01_Gen.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_Cutscene_Missle.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp104_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_10_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/FileIndex.txt' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_avina_keeper.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig05_airvents1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA30_02C_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Weap__Trcr_02_Smk.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_LAV_20_BarCup_CSO.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp104_comatose_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/XP_Silver.skn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_avina_stores.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig06_mira_welcome_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA30_02C_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ShieldImpacts_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_APL_CinePallet_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp104_logs_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.stp' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_asari_employee03.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig04_mira_off_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA20_A_Arrival_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Weap__Muzzle.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_APL_INT_CinTool1_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/DSG/BIOA_JUG70_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/MassEffectLauncher-MCE.png' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_avina_embassy.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig05_airvents1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA30_02_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ImpCrust_Generic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_APL__Cinematic_Helper__.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC40/sp104_comatose_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR50_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.ppf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_asari_employee01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig03_sentry_face_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA20_A01_Arrival_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Shield.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_APL_Cin_GRN.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_amb_crazyfemale_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR30_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/EA_Help_Fr.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_asari_employee02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig04_mira_off_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/CIN/BIOA_STA20_A_Arrival_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ImpCrust_Cryo_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOA_APL_Cin_STA70PODIUM.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR40_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/EA_Help_NL.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_asari_client02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig28_elv_decon_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ImpCrust_Fusion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG__FC_DefaultCamera__.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_amb_crazy_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR30_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_asari_companion.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig28_elv_decon_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA70_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_GethDropTro_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_Common_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_amb_crazyfemale_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR30_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/EA Customer Service Tool v1.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_zabaleta.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig27_elv_roof_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_GethEnergyDrain_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_Placeables_DockingArm.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_amb_bioticleader_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/EA_Help_UK.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_asari_client01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_client01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Geth_Mem_Metal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_TYPES.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_amb_crazy_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/EA_Help_Da.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_riot1_male.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig26_elv_reactor_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_CRT_GethDeath_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_ArtPlaceableCommonParts.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp109_crimeboss_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/UnrealScriptTest.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_samesh.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig27_elv_roof_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/ART/BIOA_STA60_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_GasBag_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_Door_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC30/sp125_amb_bioticleader_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/BIOC_BaseDLC_UNC.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_reporter.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig24_tram_60_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Geth_AntiTank_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_REF_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp106_trig01_supplies_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/PlotManager.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_riot1_female.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig26_elv_reactor_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Cin_spaceRail.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV40_APL_DOR_DoorLarge02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/UNC22/sp109_crimeboss_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/PlotManagerMap.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_parks_wealthy.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig23_trams_off_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02statue_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Cin_WarpTunnel.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV40_APL_DOR_DoorSmall01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_friendly_security_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/IpDrv.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_amb_religious_argue.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig24_tram_60_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02statue_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Cin_Plasma.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_JUG80_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_garrus_doctor_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/OnlineSubsystemLive.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_escape.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig22_juleth_ambush_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02D_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_CIN_SpaceBattles_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV40_APL_DOR_DoorLarge01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_fists_guards02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Engine.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_executor.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig23_trams_off_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02D_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Cin_Debris_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_JUG70_APL_DOR_celldoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_friendly_security_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/GameFramework.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_elcor_diplomat.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig21_fail_coolant_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02C_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Cin_MassRelay.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_JUG70_APL_DOR_celldoor02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_fists_guards01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_StrategicAI.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_emporium_shopkeep.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig22_juleth_ambush_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02C_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/EA_HELP_DE.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ZombieAttack_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_JUG00_APL_DOR_Door02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_fists_guards02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/LAY/BIOA_WAR20_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Core.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_crimeboss.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig19_rachni_encounter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_ZombieGib_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_JUG20_APL_DOR_Door01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_fist_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03a_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_Powers.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_elcor_ambassador.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE50/ice50_trig21_fail_coolant_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_Ion_Death.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_ICE_APL_DOR_Door01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_fists_guards01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03b_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_QA.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_chorban.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_3_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_XModSet_Plasma_Death_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_JUG00_APL_DOR_Door01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_expat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOC_WorldResources.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_chorban_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_3_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env__BASE_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_ICE50_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_fist_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_Design.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_bosker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_01A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env__FIRE_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_ICE50_APL_DOR_tramdoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_doran_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOC_Materials.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_captain.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_RBT_TNK_Attack01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_ICE20_APL_DOR_Door02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_expat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_02a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOC_VehicleResources.u' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_banter_02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_WormNeck_Projectile_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_ICE20_APL_DOR_Door_E_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_doctor_michel_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_bartender.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_scientist_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Rbt__Death_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/war50_door_cso.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_doran_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_guard_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_RBT_DRO_Death_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_FRE10_APL_DOR_Door01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_chorban_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_guard_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_RachniGib.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_STA70_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_doctor_michel_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_avina_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_guard_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_07A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_RAD_Attack01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_STA70_APL_DOR_ElevDoor02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_recruit01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR50_03_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sta20_banker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_guard_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_07A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_MUS_Spawn_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_STA30_APL_DOR_ElevDoor02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_13_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_rita_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR50_13_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_20_escape.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_barricade_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_06consort_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_ProtheanAvatar_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_STA60_APL_DOR_Door01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_14_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_quarian_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR40_06_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_20_xeltan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_barricade_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Maw_Spawn_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_STA20_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_recruit01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR50_03_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_STA_20_A_Waking.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_barricade_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_MTent_Spawn_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_STA30_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE50_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_quarian_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR30_02I_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_20_companion.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_ambient_barricade_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_06consort_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_KRO_ReGen_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_NOR10_APL_DOR_InnerDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_quarian_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR40_06_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_rom.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_alestiaiallis_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Maw_Attack_01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_PRO10_APL_DOR_CabDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_post_harkin_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_STA_20_A_Arrival.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE60/ice60_alestiaiallis_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_GethRadiationBurst_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_NOR10_APL_DOR_AirDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_quarian_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_05a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_Pro_20_powell_box_move.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_04C_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Crt_Husk_Tesla_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_NOR10_APL_DOR_DropDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_jenna_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04c_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_AL.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_giannaparasini_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Embers_02_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LOS10_APL_DOR_ElevDoor02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_post_harkin_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_20_E_RedShirt.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_anoleis_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_04B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Firefly_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LOS40_APL_DOR_ArchiDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_jax_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_20_I_Spectre_3.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_04C_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Earthquake.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV70_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_jenna_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04a_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_Pro_20_E_Asari.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_investigator_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_04A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Embers_01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LOS10_APL_DOR_ElevDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_harkin_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03f_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_pro_20_e_asari_sovpass.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_anoleis_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/STA/DSG/BIOA_STA20_04A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_DustFalling_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV60_APL_DOR_Door01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_jax_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_20_C_Artifact_male.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_hotel_doorman_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_dustplumes_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV60_APL_DOR_Gate01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_garrus_doctor_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03e_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_20_D_Artifact_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_investigator_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Dragonfly_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLO_NOR10_DropDoor_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_harkin_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03f_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_Pro_10_headscientist_punchout.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_corpguard_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_dustDevil.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLT_WAR20_Cargo01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG40_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_01_rita_complains_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03d_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_pro_10_husks_reveal.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_hotel_doorman_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/gameplay_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Crawling_Bugs_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLO_ICE_QueenTank_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/BIOA_JUG00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_02_jennas_contact_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03e_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_WAR_30_G_Death_Complete.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_corpguard_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Debris.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLO_JUG70BRIDGE_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG20_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig03_schells_thrown_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03c_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_war_30_geth_tower.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_corpguard_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_BloodDecals_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLO_DockingArm_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE60_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_01_rita_complains_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03d_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_war_20y_flyby2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_male_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_ColdBreath_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLO_ICE_QueenDock_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/BIOA_JUG00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_threatens_doctor_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03b_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_War_30_A_Reveal.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_corpguard_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Ashes_01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_VentCover_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG70_07_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig03_schells_thrown_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_03c_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_WAR_20_Z_Departure.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_male_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Birds_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Piles/BIOG_Bunker_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG70_14_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_stripperseat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_12a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_war_20m_zhou.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_male_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env__SKIES__Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Movers/BIOA_APL_MOV_STA70PODIUM_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG70_05_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_threatens_doctor_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_12a_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_unc_rover.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_opold_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/CIN/BIOA_PRO20_E_Asari_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env__Steam_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOA_APL_STD_Planter.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG70_07_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_septimus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_11a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_war40_armature_reveal.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_rafaelvargas_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/CIN/BIOA_PRO20_E_Asari_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/JUG_80_07_CIN_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_CompCon_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG20_A_FlyBy_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_stripperseat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_60_garrus_intro.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_mallenecalis_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/CIN/BIOA_PRO10_A_Flyby_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Asari_TeleDisrupt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_ElevConsole_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/CIN/BIOA_JUG20_A_FlyBy_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_schells_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_10b_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_60_q_ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_opold_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/CIN/BIOA_PRO10_A_Flyby_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_WAR50_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOA_APL_INT_LIFEPOD_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_11_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_septimus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/startomg.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_30_krogan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_maekomatsuo_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/CIN/BIOA_GLO00_A_Opening_Flyby_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOG_V_Env_Suns_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOA_APL_INT_ScanArm_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG80_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_scenicview_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_10a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/easmall.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_60_gambler.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_mallenecalis_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/CIN/BIOA_GLO00_A_Opening_Flyby_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_WAR30_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_war40_APL_DOR_Door01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_schells_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_10b_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/toplogo.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_sta_30_escape.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_lorikquiin_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_WAR40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_WAR40_APL_DOR_Smalldoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_rita_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_abti.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_STA_30_F_Docking.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_maekomatsuo_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC_CIN_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_JUG_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_scenicview_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_10_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_abtw.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_STA_30_Departure.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_lilihierax_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_WAR20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_LAV_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_turianguard_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_abgw.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_STA_30_Departure_Fast.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_lorikquiin_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC90_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_END_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_wrex_at_fists_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_abte.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp104_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_kairastirling_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_11_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC99_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_ICE_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_gangmember_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_abge.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp105_amb_enlisted_female.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_lilihierax_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC60_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_NCA_VOL_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_turianguard_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_abgi.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp104_comatose.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_inamorda_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC80_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/FaceFX_Assets/BIOG_FaceFX_Assets.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/JUG/ART/BIOA_JUG70_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_doran_reacts_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_05b_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp104_logs.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_kairastirling_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC42_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_SAR_MHED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_gangmember_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/TOP BA2.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp102_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_giannaparasini_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC50_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_NCA_ELC_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_choras_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02F_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Top ba1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp103_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_inamorda_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC30_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Player/BIOG_PLR_Male_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_doran_reacts_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02G_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp102_data_module.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig09_maeko_post_garage_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HLSL/BioSpriteTranslucent.hlsl' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_END_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_ai_conv3_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02E_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp102_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig10_anoleis_arrest_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Electronic_Arts_Technical_Support.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Decal_metal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_Turian_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE25_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_choras_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02F_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp100_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig08_maeko_dbl_homocide_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HLSL/BioShadowDepth.hlsl' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Decal_stone_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Player/BIOG_PLR_Female_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE25_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_ai_conv2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02C_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/top ba1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp101_garoth.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig09_maeko_post_garage_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HLSL/BioShadowDepthTest.hlsl' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Decal_blast_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_Pilot_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_13_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_ai_conv3_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02D_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/TOP BA1.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_zhu_lift.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig07_garage_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support_hha.hhk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Decal_glass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_Quarian_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE25_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_ai_conv1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whform.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp100_on_the_move.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig08_maeko_dbl_homocide_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/DSG/BIOA_PRO10_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Shaders/HLSL/BioLineBloomPostProcess.hlsl' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Bullet_Imp_Water.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_HumanMale_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_12_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_ai_conv2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whframes.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_War_50_Timber-08.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig06_insights_closed_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.hhc' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Carnage_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_Krogan_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_13_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_02_jennas_contact_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/ehlpdhtm.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_war_50_varren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig07_garage_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Electronic_Arts_Technical_Support.hhk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Blood.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_ARM_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_trig_ai_conv1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whfhost.js' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_WAR_30_J_Enlightenment.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig04_gianna_intercept_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_BloodSS.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_HGR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_khalisah_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/WinDrv.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_war_40_r_treachery.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig06_insights_closed_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_Warp_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Geth/BIOG_GTH_STP_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_krogan_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/XWindow.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp115_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig03_gianna_refers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_Weaken_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Geth/BIOG_GTH_TRO_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_jahleed_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/UnrealEd.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp116_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig04_gianna_intercept_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_TK_Attack01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_ASA_HGR_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_06_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_khalisah_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR30_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/UnrealScriptTest.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp114_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig02_maeko_greet_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_TK_Impact01_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Geth/BIOG_GTH_HUB_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_girard_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/Launch.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp114_triggers.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig03_gianna_refers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_00_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_Lift_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_ASA_HGR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_14_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_jahleed_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/DSG/BIOA_WAR20_13_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/Startup.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp111_transmission.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_rafaelvargas_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_Stasis_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_ASA_HGR_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_15_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_chellik_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/BIOA_UNC93_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/Engine.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp111_trap.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig02_maeko_greet_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_Barrier_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOG_PRO_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_13_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_girard_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/CIN/BIOA_UNC93_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/IpDrv.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp110_researcher.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig04_open_boathouse_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_B_ChargeInflux.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_ASA_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_13_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/SND/BIOA_UNC92_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/Editor.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp111_biotic.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig05_chilly_krogan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOG_Hench_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_chellik_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/BIOA_UNC93.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/EditorTips.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp109_crimeboss.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig03_tunnel_sealed_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_flesh_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOG_MultiWorld_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_12_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/SND/BIOA_UNC92_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/Core.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp110_distress_call.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig04_open_boathouse_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Water_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_UNC_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_09_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/SND/BIOA_UNC92_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/JPN/Descriptions.jpn' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp107_datalog.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig15_nuked_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Grenades_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_WAR_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_zabaleta_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/LAY/BIOA_UNC92_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp108_diplomat.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE25/ice25_trig03_tunnel_sealed_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/LAY/BIOA_PRO10_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/EA_HELP_CZ.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Mud_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_NOR_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/SND/BIOA_UNC92_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp105_trig01_distress.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig14_gianna_hint_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Rubber_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_STA_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_xeltan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/LAY/BIOA_UNC92_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp106_trig01_supplies.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig15_nuked_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_leaf_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Quarian/BIOG_QRN_ARM_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_zabaleta_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/LAY/BIOA_UNC92_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp105_amb_enlisted_male.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig13_liara_disquiet_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren_Imp_Moss_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Salarian/BIOG_SAL_ARM_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_07_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_trig_here2see_chellick_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/sp105_mariedurand.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig14_gianna_hint_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren__Ion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_HGR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_wrex_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/LAY/BIOA_UNC92_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_70_c_attack_good.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig12_garage_ambush_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren__Plasma_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_HGR_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_06_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_trig_01_jahleedfears_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_70_sarendead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig13_liara_disquiet_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren__Generic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_HED_PROMorph.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_trig_here2see_chellick_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_70_b_relay.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig11_si_guards_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren__HighExplosive_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_HED_Wrex_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_talitha_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_70_c_attack_evil.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig12_garage_ambush_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren__Cryo_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_ARM_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_trig_01_jahleedfears_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/small_rachni.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig10_anoleis_arrest_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Gren__Fusion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_ARM_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_snap_inspection_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_70_b_control.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_trig11_si_guards_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Decal_wood_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_HGR_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_talitha_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/saren_monster.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/unc00_popup_text_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_GethGib.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_ARM_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_requisition_officer_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/shiala_asari.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/war20_trig_skyway_warning_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/SND/BIOA_PRO10_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_water_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_HGR_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_06_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_snap_inspection_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/saren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/test_pick_henchmen_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_wood_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_HGR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_officer_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/saren_flyer.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/unc00_popup_text_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_sand_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_ARM_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_requisition_officer_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_sovereign.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/sp101_corpse_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_stone_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_normandy_mechanic_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/BIOA_WAR00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_trigger_charges.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/test_pick_henchmen_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/PLC/BIOA_PRO10_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_robot_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_HGR_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_13_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_officer_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/BIOA_WAR00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_powell.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/jb_workbench_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_03_GM_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_Rubber_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_HGR_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_krogan_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/SND/BIOA_UNC93_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_saren_cutscene.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/sp101_corpse_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_moss_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/Grenade.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_normandy_mechanic_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/SND/BIOA_UNC93_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_nihlus_saren_cutscene.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ice50_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_plastic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/IW_grenade.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_03_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_flux_patron02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/LAY/BIOA_UNC93_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_notice_beacon.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/jb_workbench_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_leaf_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_BZK_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_market_buyer_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/LAY/BIOA_UNC93_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ice_20_a_flyby.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/GlobalTlk.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_12tali_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_metal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_SNP_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_flux_patron01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/DSG/BIOA_UNC93_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ICE_20_H_Arrest.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ice50_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_HexBarrier_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_ASL_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE50_15_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_flux_patron02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/LAY/BIOA_UNC93_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_GLO_00_Sovereign.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/elev_exit_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_12_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_Ice_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_BLS_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_flux_customers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/DSG/BIOA_UNC93_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ICE_10_A_FlybyC.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/elev_exit_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_12tali_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_glass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_HGR_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_flux_patron01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC93/DSG/BIOA_UNC93_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_glb_00_A_opening_3.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/elev_enter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_11ash_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_grass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_HIR_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE25_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_patron02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_glo_00_endgood.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/elev_enter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_gases_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_HED_PROMorph_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_flux_customers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_glb_00_A_opening.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end70_elevator_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_11_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_C_Imp_generic_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_HGR_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_patron01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_glb_00_A_opening_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END80/end80_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_11ash_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_END70_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_ARM_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_patron02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_saren_suicide.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end70_airlock_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_JUG70_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_ARM_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_customers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_sovereign_dead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end70_elevator_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_JUG80_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Salarian/BIOG_SAL_HGR_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_patron01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/EA_logo(Silver).jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_90_f_sovereigndead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end20_avina_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_HED_PROMorph.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_ARM_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_cops_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_a_nodeclose.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end70_airlock_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_09_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_HIR_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Salarian/BIOG_SAL_HED_PROMorph_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_customers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_90_c_sovereigngood.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end00_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_ARM_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Salarian/BIOG_SAL_HGR_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA30/sta30_wrex_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_90_e_infusion.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end20_avina_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_HIR_PRO.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_wpn_switch.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_choras_cops_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_80_a_gravity.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/CHA00/unc_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_ARM_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_xmod_deaths.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_black_market_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR30_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_end_80_c_uplink.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END70/end00_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_00_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_ARM_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_sgeplse.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_14_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_chorban_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR40_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_80_r_wounded.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/CHA00/combat_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_HED_PROMorph_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_vfx.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/SND/BIOA_ICE20_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_banter_02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR30_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_80_sarenentry.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/CHA00/unc_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_13_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_SCI10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_inter_plcble.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_12_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_black_market_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR30_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_80_c_nukeversion2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/CHA00/cha00_banter_ques_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_omnitool.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_13_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_80_nukeactivation.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/CHA00/combat_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_FRE10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_geth_rdtnbrst.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_banter_02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR20_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_70_k_explosion.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/war20_trig_skyway_warning_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_09ROM_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_GLO_00_B_Sovereign_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_grenades.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR30_02G_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_70_x_freakout.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/CHA00/cha00_banter_ques_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_GXM10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_bullet_impacts.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR30_02I_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_70_beacon.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_saren2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_TER10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_env_vfx.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_assassins_dispatched_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR30_02A_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_70_j_warhead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_saren_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LAV60_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Vehicles/snd_rover_v5.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR30_02B_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_JUG_20_A_Flyby.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_final_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LAV70_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_blood.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-02.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_assassin_ambush_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR20_03c_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_40_d_nukeevac.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_saren2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LAV20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Vehicles/snd_rover_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-03.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_assassins_dispatched_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR20_A_FlyBy_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/gameplay.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ice_60f_regiside.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_cutscenes_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LAV40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Vehicles/snd_rover_v4.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/FitGirl releases on KAT.url' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_market_conversation_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR20_01_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ICE_70_D_Tartakovsky.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_final_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/LAY/BIOA_NOR10_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_JUG80_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Vehicles/snd_normandy.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-01.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_assassin_ambush_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/CIN/BIOA_WAR20_03c_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ice_60d_queen.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_council_dead_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LAV00_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Vehicles/snd_rover.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_market_buyer_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_16_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ice_60e_freedom.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_cutscenes_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_JUG40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Geth_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/FitGirl releases on 1337x.url' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA60/sta60_amb_market_conversation_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_17_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ice_20_hopper_reveal.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_council_alive_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_Jug70_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Global_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_elcor_ambassador_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_14_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_ICE_20_I_Flyby2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_council_dead_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/UnrealEd10_25.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Ambient_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Burnout 3 - Takedown (USA)/Burnout 3 - Takedown (USA).iso' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_elcor_diplomat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_15_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_Pro_10_D_Ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_choice_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_Jug20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Asari_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE20_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_crimeboss_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_12_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_10_F_Ashley.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_council_alive_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/testVolumeLight_VFX.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_UNC_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_14_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Super Mario Sunshine (USA).7z' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_elcor_ambassador_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_13_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_player_table.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END80/end80_salarians_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/TrevsTests.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_WAR_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_14_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_chorban_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_PRO_10_A_Flyby.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_choice_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/RefShaderCache-PC-D3D-SM3.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_STA_AMB_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_crimeboss_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/WAR/ART/BIOA_WAR50_11_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/install.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_nor_20d_melding.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END80/end80_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Startup_int.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_STA_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_chorban_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/LAY/BIOA_UNC83_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_oculon_approach_dream.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END80/end80_salarians_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE50_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_NOR_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_chorban_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/LAY/BIOA_UNC83_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_los_40_j_attack.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_female_2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_12_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA30_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_PRO_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_captain_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/DSG/BIOA_UNC83_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_los_end_rover.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_male_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ROM_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_JUG_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_chorban_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/DSG/BIOA_UNC83_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_los_10_c_landing.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_female_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_Sign01_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_LAV_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_bosker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/CIN/BIOA_UNC83_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_los_10a_flyby.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_female_2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_PRO_10_A_Flyby_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_ICE_AMB_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/SSX 3 (USA)/SSX 3 (USA).iso' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_captain_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/DSG/BIOA_UNC83_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/go.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_lav_70_armature_drop.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_amb_interview_salarian_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_PRO_20_C_Artifact_male_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_ICE_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/MD5/QuickSFV.EXE' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_bartender_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/BIOA_UNC83.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/Engine.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_lav_70_collapse.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_ambient_business_female_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/PLC/BIOA_NOR10_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_PRO10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/VFX/snd_xmods.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/MD5/QuickSFV.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_bosker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/BIOA_UNC83_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/IpDrv.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_nukedetonation2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_amb_interview_human_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_PRO20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOA_END_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banter_02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/SND/BIOA_UNC82_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/Editor.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_o_mexecution.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_amb_interview_salarian_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_11_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_NOR10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Turian_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/MD5/fitgirl-bins.md5' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_bartender_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/SND/BIOA_UNC82_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/EditorTips.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_80_sarenversion2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice00_popup_text_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_PRO00_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Turret_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_hanar_religious_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/LAY/BIOA_UNC82_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/Core.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/snd_jug_80_x_outrun.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice20_amb_interview_human_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS50_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Terminus_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/Verify BIN files before installation.bat' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_human_ambassador_enter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/SND/BIOA_UNC82_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/Descriptions.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_caleston_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/FRE31/sp111_trap_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_NebulaeClouds_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Thorian_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-optional-russian-complete.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_garrus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/LAY/BIOA_UNC92_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseQA.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_caleston_done.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/ICE20/ice00_popup_text_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS30_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_SocketSuperModel.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-optional-russian-text-only.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_hanar_religious_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/LAY/BIOA_UNC82_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseUI.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_navigator.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/FRE31/sp111_biotic_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_TechBeacon_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE25_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-optional-german.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_female_diplomat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/LAY/BIOA_UNC82_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseGame.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_oculon_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/FRE31/sp111_trap_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Rachni_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-optional-italian.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_garrus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/LAY/BIOA_UNC82_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseInput.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_landing_bay.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/END90/end90_saren_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Saren_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-optional-bonus-content.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_family_argue_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseEditorUserSettings.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_landing_bay_cutscene.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/FRE31/sp111_biotic_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS00_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Player_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-optional-french.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_female_diplomat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseEngine.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_joker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO20/BIOA_PRO_20_C_Artifact_male_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_LOS10_A_Flyby_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Quarian_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-04.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_executor_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseEditor.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_kaiden.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO20/BIOA_PRO_20_D_Artifact_2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/ART/BIOA_PRO10_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Krogan_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Mass Effect [FitGirl Repack]/setup-fitgirl-05.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_family_argue_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Config/BaseEditorKeyBindings.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_engineer.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_E_Redshirt_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/BIOA_PRO00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC21_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Pilot_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_escape_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/AutoLoad.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_jenkins.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_I_Spectre_3_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/PRO/BIOA_PRO00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_HumanMale_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_executor_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/BIOCredits_DLC_Vegas.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_cutscene_oculon_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_A_Flyby2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC11_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Jenkins_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_emporium_shopkeep_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_doctor.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_A_Flyby3_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/SND/BIOA_NOR10_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC03_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_15_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_escape_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_comm_room.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/NOR20/BIOA_NOR_20_D_Melding_B_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_00_DS2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC04_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/BIOG_HumanFemale_Hench_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/SSX Tricky (USA).7z' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_elcor_diplomat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/CIN/BIOA_UNC84_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_comm_room2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO10/BIOA_PRO_10_A_Flyby1_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_01_DS2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_TER10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_Asari_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Super Mario Bros. 3 (USA).zip' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_emporium_shopkeep_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_backgrounds.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/NOR20/BIOA_NOR_20_D_Melding_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_12_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_UNC02_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/PartyMembers/BIOG_PTY_HumanFemale_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_14_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/SSX 3 (USA).7z' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig04_remember_me_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/BIOA_UNC84.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_captain.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/NOR20/BIOA_NOR_20_D_Melding_A_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_12_DS1_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA90_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_TUR_SAR_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/SSX On Tour (USA).7z' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_01_xeltancomplains_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/BIOA_UNC84_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_sal_comstore.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS40/BIOA_LOS_40_J_Attack_SEQ_06_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_11_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA_30_Departure_Fast_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_ZMB_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Burnout 3 - Takedown (USA).zip' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_terra_firma_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/SND/BIOA_UNC83_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_trig01_4estate_hackett.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS40/BIOA_LOS_40_J_Attack_SEQ_07_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_11_DS1_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA70_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_SAL_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Chrono Trigger (USA).zip' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig04_remember_me_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/SND/BIOA_UNC83_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_req_officer.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LAV70/BIOA_LAV_70_H_Collapse_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_09_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA80_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_TUR_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE50_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_samesh_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/webhelp.jar' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_sal_captainkirrahe.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS10/BIOA_LOS_10_C_Landing_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_10_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA40_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_KRO_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_05_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Super Mario Bros. 3 (USA)/Super Mario Bros. 3 (USA).nes' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_terra_firma_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC83/LAY/BIOA_UNC83_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/DialogLogo128x128.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_noveria_done.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE70/BIOA_ICE_70_D_Tartakovsky_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_07_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA60_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_MRC_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_reporter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/CIN/BIOA_UNC90_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/WinDrv.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_noveria_report.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG70/BIOA_Jug_70_X_freakout_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_08_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_HMF_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/SSX Tricky (USA)/SSX Tricky (USA).iso' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_samesh_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/DSG/BIOA_UNC90_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/XWindow.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_leaving_oculon.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Waking_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_05_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_STA30_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_HMM_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_receptionist_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/BIOA_UNC90.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/UnrealEd.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_noveria_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_sta_20_escape_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_06_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_NOR.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_ASA_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/SSX On Tour (USA)/SSX On Tour (USA).iso' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_reporter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/BIOA_UNC90_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/UnrealScriptTest.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_ilos_open.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_SEQ10_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_04_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Zombie/BIOG_ZMB_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Humanoids/BIOG_GTH_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_03_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/$RECYCLE.BIN/S-1-5-21-3079317735-2231223055-980023791-1001/desktop.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_negotiator_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/SND/BIOA_UNC84_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/Launch.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_joker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_SEQ14_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_04_DS1_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_TurianFrigate.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Creatures/BIOG_NCA_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/System Volume Information/WPSettings.dat' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_receptionist_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/SND/BIOA_UNC84_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Engine/Localization/INT/Startup.int' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_feros_report.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_SEQ03_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_03_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LOS40_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Creatures/BIOG_RBT_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_02_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_male_diplomat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_ilos_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_SEQ05_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_03_DS1_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Dmgd_Car_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Creatures/BIOG_AMB_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_negotiator_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/SND/BIOA_UNC84_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_empty_locker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_SEQ01_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_01patton_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/index.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_END90_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Appearances/Creatures/BIOG_CBT_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE20_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/System Volume Information/IndexerVolumeGuid' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_human_ambassador_enter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_feros_done.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_SEQ02_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_01patton_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/other_index.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Crate_XLarge_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/War_world/snd_war_50_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_male_diplomat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_caleston_report.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_02_Leadin_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_01escape_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/ealogo.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_TurianFighter.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Physics/snd_phys_proto.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_14_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_volus_diplomat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_confrontation.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA20/BIOA_STA_20_A_Arrival_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_01escape_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/greyback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE_20_A_FlyBy_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/War_world/snd_War_30_A_Reveal_mix.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_xeltan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig02_d_nihlus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_01_Clearing_Exit_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/book_open.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_SaveLoad.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/War_world/snd_war_40_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_volus_ambassador_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig05_nihlus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_01_Clearing_Exit_Male_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/bookclosed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LOS40_APL_DOR_FFDoor_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/War_world/snd_war_20_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_volus_diplomat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/LAY/BIOA_UNC84_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig02_a_river_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_01_Clearing_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09liara_DS2_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Market_Stall_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/War_world/snd_war_30_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/LAY/BIOA_ICE60_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_turian_religious_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig02_c_bodies.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ROM/BIOA_ROM_01_Clearing_Enter_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ICE25_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_sand.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_volus_ambassador_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC84/DSG/BIOA_UNC84_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_headscientist.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO20/BIOA_PRO_20_D_Artifact_2_Seq2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09kaidan_DS2_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Prothean/BIOG_PRO_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/War_world/snd_war50_valvegame.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_fan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_m_scientist02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/PRO20/BIOA_PRO_20_E_Asari_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09liara_DS2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Veh_Diag_Bench_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_rock.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_turian_religious_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/DSG/BIOA_UNC92_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/indoctrinated_salarian_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09ashley_DS2_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Piles/BIOG_APL_UNC_Misc_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_rover.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_ai_machine_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/BIOA_UNC92_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_banter_02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/joker_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09kaidan_DS2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Piles/BIOG_APL_STD_ThorianPods.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_lava.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_fan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/CIN/BIOA_UNC92_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_ash.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/human_male_2_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09_DS2_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LOS30_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_rain.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_03_flagship_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/SND/BIOA_UNC90_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/inamorda_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09ashley_DS2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Salarian/BIOG_SAL_ARM_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_grass.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_ai_machine_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC92/BIOA_UNC92.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/bgrd_main.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_virmire_open.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/human_female_2_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_01_DS2_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_ARM_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_ice.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_02_lovescompanion_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/SND/BIOA_UNC90_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_virmire_report.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/human_male_1_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS2/BIOA_NOR10_09_DS2.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_WAR50_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_sand.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_03_flagship_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/SND/BIOA_UNC90_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_virmire_approach.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/garrus_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06locker_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_WAR40_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_unc_cometstorm.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE25_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_01_xeltancomplains_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/LAY/BIOA_UNC90_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_virmire_done.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/human_female_1_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06locker_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_SAR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/saren_flyer_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_trig_02_lovescompanion_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/LAY/BIOA_UNC90_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_trig03_callhome.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/asari_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06kaidan_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Oculon.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/saren_monster_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_V_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_companions_chatter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/LAY/BIOA_UNC90_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor20_trig04_airlock.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/ashley_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06kaidan_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE25_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/husk_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_companions_chatter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/LAY/BIOA_UNC90_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_husk_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR50/BIOA_WAR_50_B_Lizbeth_1_1_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/lysander_kostas_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_09_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta00_cabarrival_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/DSG/BIOA_UNC90_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_m_farmer01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Gui/snd_gui_computer.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ICE70_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta00_popup_text_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/DSG/BIOA_UNC90_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/check.jpg' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_end_cutscene_matriarch.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA60/BIOA_STA_60_Quarian_Ambush_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_GethCruiser2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_stalker_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta00_cab_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/DSG/BIOA_UNC90_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_f_farmer01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/WAR30/BIOA_WAR_30_J_enlightenment_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_GLO_00_A_Opening_FlyBy_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_recon_drone_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta00_cabarrival_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC90/DSG/BIOA_UNC90_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_cole.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA30/BIOA_sta_30_krogan_cutscene_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_04A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LOS20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_rocket_drone_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_10_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sp_news_vids_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/DSG/BIOA_UNC73_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro20_end_cutscene_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA60/BIOA_STA_60_NormandyEscape_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_04A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_WAR30_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_juggernaut_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta00_cab_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/LAY/BIOA_UNC73_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_09_shed01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/cha00_trig_wrex_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LAY10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_prime_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sp_follower_interject_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/DSG/BIOA_UNC73_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_10_shed02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/cha00_trig_wrex_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ICE20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_assault_drone_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sp_news_vids_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/DSG/BIOA_UNC73_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_04_captain_dead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/cha00_krogan_wrex_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ICE60_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/geth_destroyer_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sp108_diplomat_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/BIOA_UNC73.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_08_probe.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/cha00_krogan_wrex_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA70_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/BenH_Test_SoundSetVO.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sp_follower_interject_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/CIN/BIOA_UNC73_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/black background.JPG' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_02_b_gasbag.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/turian_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOA_APL_INT_NorDocTunnel_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/creeper_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_charges_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/SND/BIOA_UNC71_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_03_b_river_ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/wrex_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_GethCruiser.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/arcelia_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sp108_diplomat_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/SND/BIOA_UNC71_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig_jenkins.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/sta30_officer_01_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_08liara_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_END80_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/armature_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_10_bodies_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/LAY/BIOA_UNC71_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trigger_01_outside_ship.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/tali_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_08liara_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LOS10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_ss_ai.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_charges_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/LAY/BIOA_UNC71_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig06_c_cresting_ridge.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/salarian_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_ICE50_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_ss_carnabug.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_riot1_female_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/DSG/BIOA_UNC71_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/pro10_trig08_nihlus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/saren_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA80_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_space_cow.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_riot1_female_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/DSG/BIOA_UNC71_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_slv_fanatic01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/player_f_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_07wake_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LOS50_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_space_monkey.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_reporter_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/DSG/BIOA_UNC71_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_slv_fanatic02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/player_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_07wake_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_JUG40_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_rachni_worker.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_reporter_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/DSG/BIOA_UNC71_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_sal_prisoner.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/liara_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_Jug20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_shckzmb.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_religious_argue_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/BIOA_UNC71_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_sal_psyrana.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/matriarch_benezia_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_ROV_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_maw.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/PLC/BIOA_ICE60_11_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_religious_argue_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/CIN/BIOA_UNC71_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/kaidan_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06wake_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE70_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_rachni_soldier.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_04A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_parks_wealthy_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/LAY/BIOA_UNC80_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_kro_docdroyas.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/krogan_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06wake_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Achievement.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_gth_armtre_big.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_parks_wealthy_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/LAY/BIOA_UNC80_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug40_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/HMM_HIR_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06lockerl_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LAV60_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_hopper.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_negotiator_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/LAY/BIOA_UNC80_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_asa_compalethea.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/NodeBuddies.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06lockerl_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_TER20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_gas_bag.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_negotiator_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/LAY/BIOA_UNC80_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug40_captainupdate.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EngineMaterials.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06lockerk_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_END80_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_geth_vox.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_hanar_religious_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/DSG/BIOA_UNC80_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug40_kirrahe_checksin.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/GlobalCookedBulkDataInfos.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06lockerk_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_FRE10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_creature_anims.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_hanar_religious_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/DSG/BIOA_UNC80_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_wrex.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EditorMeshes.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06lockera_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/BLUEBACKGROUND.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LAV70_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_firebeetle.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_family_argue_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/DSG/BIOA_UNC80_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug40_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Engine_MI_Shaders.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DSG/BIOA_NOR10_06lockera_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/BLUEBACKGROUND.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_MIN00_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/shiala_asari_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_family_argue_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/DSG/BIOA_UNC80_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_trig_wrex_killed.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/DELETEME_TEXTURES_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_END20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/small_rachni_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_crimeboss_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/BIOA_UNC80_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/EditorMaterials.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Telemetry/snd_telemetry.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_14_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_crimeboss_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/CIN/BIOA_UNC80_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_sal_captainkirrahe.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/DELETEME_GETH_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_GXM10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Vehicles/flybys.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_15_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_employee02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/snd/BIOA_UNC73_02_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_sal_comstore.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/DELETEME_GUNTextures.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/x06_player_final_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_12_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_employee03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/BIOA_UNC80.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/EA_HELP_SV.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_cutscene_escape.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_P_Potted_Plant_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_WAR20_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Telemetry/snd_normandy_beeps.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_employee01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/snd/BIOA_UNC73_00_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_party_comment1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_VI_Avatar_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA60_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/x06_ash_final_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_employee02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/snd/BIOA_UNC73_01_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_asariscientist.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_P_Generator_Fix.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS40_05_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/gray-left.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_SOV.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/x06_garrus_final_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE50_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_companion_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/LAY/BIOA_UNC73_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_P_MedDiag_Equip_v2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/gray-rt.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_GalaxyMap_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/ss_gth_hdrn.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_12_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_employee01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/LAY/BIOA_UNC73_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/krogan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_MatFX_G_Ice.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS40_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_JUG00_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/varren_ss.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_client02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/LAY/BIOA_UNC81_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav60_trig02_base_fallback.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_MatFX_PlasmaStun.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS40_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/gray-left.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_ICE60_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_zombie.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_companion_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/LAY/BIOA_UNC81_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug80_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_GameProperties_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS40_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/content.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Dreadnaught.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/ss_gth_drone.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_client01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/LAY/BIOA_UNC81_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/kaidan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_GamerProfile_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS40_01_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_STD_Solar_Panel_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_varen.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_client02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/LAY/BIOA_UNC81_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug80_choice.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Equipment_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_11_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Geth_Pod_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_x06_ambient.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_10_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_zabaleta_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug80_saren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_GalaxyMap_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_11_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/content.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_STD_Geth_Wall_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_ss_keep.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_zabaleta_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_sovereign.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_CreatureAi_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/bookclosed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Bank_Machine_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_trooper.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_samesh_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_trigger.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Creatures_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/close.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_War_Cover_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_ss_geth_hub.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_07A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_samesh_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_slv_mindless03.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_CharacterCreation_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_GethTransport.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Soundsets/snd_ss_gtharmtre_sml.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_07A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_riot1_male_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_slv_mindless04.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Characters_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/book_open.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Pause_Screen.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Gui/snd_gui.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_amb_riot1_male_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_slv_mindless01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Animation_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Potted_Plant_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/End_world/snd_end.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/CIN/BIOA_UNC81_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug70_slv_mindless02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_AreaMap_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Desk_and_Chair1_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/FS_BF/snd_footsteps.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banter_02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/DSG/BIOA_UNC81_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_trig_bc.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG__Suns__.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Crate_Large_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Gui/PC_GUI_Sounds.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/SND/BIOA_UNC80_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_trig_d.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/EffectsMaterials.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Large_Computer_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Foley/snd_weapon_foley.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_04A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/BIOA_UNC81.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_trig_a.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BioEngineResources.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/search.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_STD_Geth_Pod_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/FS_BF/snd_bodyfalls.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE60_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/SND/BIOA_UNC80_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_trig_armature.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BIOG__SKIES__.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Pleasure_Pod_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Foley/snd_foly_cloth.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_11_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC80/SND/BIOA_UNC80_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_security_system_done.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BioBaseResources.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS30_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/right-ar.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_G_Hex_Barrier_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Foley/snd_veggie_foley.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_12_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_triggers_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/DSG/BIOA_UNC82_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_security_system_start.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/BioEngineMaterials.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS40_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/search.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Chair_Comf_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/war_30_h_respawn.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_banker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/DSG/BIOA_UNC82_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los10_trig_door03.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END_70_Saren_Suicide_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS30_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Red_Page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Potted_Plant_02_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Foley/snd_bottle_foley.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_stores_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/DSG/BIOA_UNC82_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_armatures_active.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END_80_C_Uplink_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS30_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/right-ar.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Cafeteria_Table_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war_50b_lizbeth.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_triggers_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/DSG/BIOA_UNC82_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los10_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END_70_C_Good_[9-10]_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Red_Book_Closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Tower_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_zhu_lift.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_keeper_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/DSG/BIOA_UNC82_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los10_trig_door00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END_70_G_Sarendead_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS30_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/Red_Browse_Right.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Crop_Bed_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_War_50_Timber-08.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_stores_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/DSG/BIOA_UNC82_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_trig04_elevator_ride.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_VFX_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_PST_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war_50_varren.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_embassy_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/BIOA_UNC82_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/AutoLoad.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/liara.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_END_70_C_Attack_Evil_[5-7]_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS10_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Concrete_Pipe_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_WAR_30_J_Enlightenment.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_keeper_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/CIN/BIOA_UNC82_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/BIOCredits_DLC_UNC.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_trig02_mining_laser.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_UseMaps_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/left-ar.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_MassRelay.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war_40_r_treachery.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_asari_employee03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/SND/BIOA_UNC81_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultQA.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_trig03_krogan_boss.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Vehicles_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/other_index.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_GalaxyMap.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice60_medbay.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/STA20/sta20_avina_embassy_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC82/BIOA_UNC82.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultStringTypeMap.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_party_comment2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_TreasureTables_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/BIOA_NOR00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/index.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_GambTable01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice60_mtc_area.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_03_b_river_ambush_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/SND/BIOA_UNC81_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultInput.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/lav70_trig01_attention.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_UI_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/left-ar.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/MicrosoftHair.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice50_main.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE25_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_04_captain_dead_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/SND/BIOA_UNC81_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultParty.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_ambient_02.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Rules_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/gray-rt.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Chair_Bar_02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice60_main.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_02_b_gasbag_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/SND/BIOA_UNC81_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultGame.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_ash.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Talents_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/BIOA_NOR00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/greyback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Prothean_Beacon_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice25_exterior.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_03_b_river_ambush_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/SND/BIOA_UNC81_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultGuiResources.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/music_unc.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Music_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_next_g.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_GalaxyMap_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice25_tunnels.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_13_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_01_outside_ship_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/LAY/BIOA_UNC81_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultEditor.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/nor10_ambient_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_PlotManager_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_prev.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_TRK_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice20_main.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_11_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_02_b_gasbag_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/LAY/BIOA_UNC81_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultEngine.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/music_bunker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_LevelUp_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_logo2.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Anthid_Lodge_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice20_marketplaza.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_12_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig_jenkins_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/LAY/BIOA_UNC61_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/gl.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/music_knossos.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/2DAs/BIOG_2DA_Movement_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_next.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_HGR_CTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_hotlabs_purge.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_01_outside_ship_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/LAY/BIOA_UNC62_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/Config/DefaultCredits.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/matriarch_benezia.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE20/BIOA_ICE_20_A_FlyBy_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_idx_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Shop.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice20_dockingbay.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig08_nihlus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/LAY/BIOA_UNC54_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whrstart.ico' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/music_bank.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE20/BIOA_ICE_20_H_Arrest_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_logo1.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_KeeperConsole.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Fre_world/snd_fre_mn.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig_jenkins_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/LAY/BIOA_UNC54_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whstart.ico' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los50_conduit.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_B_Sovereign_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_hide.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/newversion_Ball_Turret_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Fre_world/snd_unc_52_thruster.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig06_c_cresting_ridge_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los50_conduit_crash.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_C_EndGood_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_idx_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Engine_Debris_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/End_world/snd_end_80.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig08_nihlus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/whestart.ico' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los40_trig_c.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_OpeningSEQ06_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_glo_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Desk_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Fre_world/snd_fre.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig05_nihlus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los40_watcher.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_openingSEQ07_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/SND/BIOA_LOS50_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_HGR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/End_world/snd_end00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig06_c_cresting_ridge_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los40_trig_a.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_a_openingSeq01_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_02_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_fts_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_MainMenu.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/End_world/snd_end70.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig02_d_nihlus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los40_trig_b.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_openingSEQ04_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_02_DS1_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_glo_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_APL_STD_Mass_Relay_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Lav_world/snd_lav70.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig05_nihlus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los30_watcher.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_SovereignGood_Jok_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_01_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/websearch.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Vehicles/BIOG_APL_VEH_Ambient01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Lav_world/snd_lav_70_armature_drop.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_f_farmer01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/los40_oculon_attack.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/GLO/BIOA_GLO_00_A_OpeningSEQ00_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_01_DS1_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_fts_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Freighter_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Lav_world/snd_lav40_door_small.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_15_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_husk_trigger_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/DSG/BIOA_UNC54_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig10_mira_bsod.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_SovereignDead_J1_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/CIN/NOR10_01_DS2_Flyby_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_STD_Human_Wall_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Lav_world/snd_lav60.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE60_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_end_cutscene_matriarch_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/BIOA_UNC54.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig13_salarian_suicide.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_SovereignDead_J2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/DS1/BIOA_NOR10_00_DS1.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/websearch.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_HumanFighter.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_normandy_trench_e3.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_13_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_f_farmer01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/CIN/BIOA_UNC54_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig06_mira_welcome.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END80/BIOA_END_80_A_Gravity_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_11_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_ws.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Table_Cafeteria_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_normandy_trench_exit.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE50_14_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_end_cutscene_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/SND/BIOA_UNC53_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig09_coolant_clue.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END90/BIOA_END_90_E_Infusion_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_12_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_ws_g.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Containers/BIOG_APL_CON_Cargo_Container_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_jug_80_geth_flyby.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_01leave_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_end_cutscene_matriarch_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/SND/BIOA_UNC53_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig04_mira_off.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_GLO_00_C_EndGood_Seq2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_toc_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_MedDiag_Equip_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_nor_trench_entry.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_cole_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/DSG/BIOA_UNC55_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig05_airvents1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/END70/BIOA_GLO_00_C_EndGood_Seq3_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_toc_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Storageshelf_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_jug_70_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_01A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_end_cutscene_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/LAY/BIOA_UNC55_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig01_krogan_sniper.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_jealous_jerk_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab7.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_MainFrame_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_jug_80_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_01leave_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_10_shed02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/DSG/BIOA_UNC55_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig03_sentry_face.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_jealous_jerk_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab8.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_TTR_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_jug_20_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_cole_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/DSG/BIOA_UNC55_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_guard_number_two_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab5.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Fuel_Tank_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_jug_40_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_01A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_09_shed01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/BIOA_UNC55_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_mira.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_guard_number_two_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab6.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanMale/BIOG_HMM_HGR_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice70_main.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_10_shed02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/CIN/BIOA_UNC55_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig14_gianna_hint.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_courier_device_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab3.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_DestinyAscension.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Jug_world/snd_jug80_design_flyby.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_08_probe_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/SND/BIOA_UNC54_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_amb_announcements.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_courier_device_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/NOR/ART/BIOA_NOR10_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab4.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Geth_Bomb_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice60_rachniqueen.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE60_14_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_09_shed01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/BIOA_UNC55.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/EA_HELP_Bra-Pt.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig12_garage_ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_bryant_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab1.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_END20_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Ice_world/snd_ice60_seceretlabs.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE60_14_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_04_captain_dead_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/SND/BIOA_UNC54_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig13_liara_disquiet.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_bryant_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab2.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Geth_Turret_01_base_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_ice.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE60_07_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trigger_08_probe_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/SND/BIOA_UNC54_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig10_anoleis_arrest.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_ahern_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_sync.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Landing_Claw_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_rock1.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE60_12_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_sovereign_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/LAY/BIOA_UNC54_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig11_si_guards.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_ahern_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_tab0.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_SHT.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Sta_world/snd_sta_70_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE20_A_FlyBy_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_01_ridge_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/SND/BIOA_UNC54_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_scientist_4.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/2DAs/BIOG_2DA_Vegas_UI_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_prev_g.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Dstny_Ascn_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Uncharted/snd_grass.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE20_A_FlyBy_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_saren_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/LAY/BIOA_UNC54_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_sick_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Audio_Content/snd_prc2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/wht_spac.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Turian_Frigate_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Sta_world/snd_sta_30_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE20_03_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_sovereign_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/LAY/BIOA_UNC54_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_scientist_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/2DAs/BIOG_2DA_Vegas_Merge_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Turian/BIOG_TUR_HED_SAR.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Sta_world/snd_sta_60_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/CIN/BIOA_ICE20_03_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_powell_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/LAY/BIOA_UNC71_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_scientist_3.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/2DAs/BIOG_2DA_Vegas_TreasureTables_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_NebulaeClouds_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Pro_world/snd_pro20.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_saren_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/LAY/BIOA_UNC73_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_guard_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/2DAs/BIOG_2DA_Vegas_GalaxyMap_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Generator_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Sta_world/snd_sta_20_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_notice_beacon_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/LAY/BIOA_UNC61_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_scientist_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/2DAs/BIOG_2DA_Vegas_GamerProfile_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Dwnd_Satellite_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Nor_world/snd_nor10.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_powell_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/snd/bioa_unc61_00_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_barricade_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2_CCCave.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Cinematic/BIOG_GTH_PKE_APL.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Pro_world/snd_pro10.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_nihlus_saren_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/LAY/BIOA_UNC61_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_guard_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2_CCCrate.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Chair_Comf_02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Los_world/snd_los_50_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_notice_beacon_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/LAY/BIOA_UNC61_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig28_elv_decon.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Drill_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Los_world/snd_los_ele.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_nihlus_dies_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/DSG/BIOA_UNC61_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_alestiaiallis.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2_CCAhern.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_KRO_Statue.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Los_world/snd_los_30_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03D_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_nihlus_saren_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/DSG/BIOA_UNC61_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig26_elv_reactor.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/GUI_SF_PRC2_Journal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Utility.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Los_world/snd_los_40_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03E_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_m_farmer01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/DSG/BIOA_UNC61_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig27_elv_roof.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/GUI_SF_PRC2_SaveLoad.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_END90_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Lav_world/snd_lav_geth_dropship.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03C_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_nihlus_dies_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/DSG/BIOA_UNC61_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig22_juleth_ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GameObjects/Faces/BIOA_PRC2_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_UV_Lamp_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Level/Los_world/snd_los_10_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03D_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_husk_trigger_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/CIN/BIOA_UNC61_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig24_tram_60.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/GUI_SF_PRC2_GalaxyMap.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Dmg_Car_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_80_sarenversion2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_m_farmer01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/DSG/BIOA_UNC61_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig15_krogan_decon.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GameObjects/Characters/BIOA_PRC2_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOA_APL_PLT_NOR10_View01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_80_x_outrun.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_09_geth_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/SND/BIOA_UNC55_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice50_trig19_rachni_encounter.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GameObjects/Characters/BIOA_PRC2_SIM_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Crate_Med_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_80_r_wounded.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03A_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_10_bodies_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/BIOA_UNC61.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig08_tram.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_wise_turian_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Truck_Jack_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_80_sarenentry.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03A_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_08_thresher_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/SND/BIOA_UNC55_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig09_assault_complete.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_wise_turian_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Escape_Pod_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_80_c_nukeversion2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_09_geth_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/SND/BIOA_UNC55_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig05_talin_frets.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_ochren_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Contain_Cells_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_80_nukeactivation.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/DSG/BIOA_ICE20_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_07_sniper_attack_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/LAY/BIOA_UNC55_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig06_science_joke.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_ochren_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/BIOG_VEH_Ball_Turret_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_70_k_explosion.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_08_thresher_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/LAY/BIOA_UNC55_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_talinsomaai.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_krogan_frat_boy_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_PC_CharacterCreation.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_70_x_freakout.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_06_control_panel_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/SND/BIOA_UNC62_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig04_lab_ambush.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/prc2_krogan_frat_boy_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Rachni_Egg_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_70_beacon.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_07_sniper_attack_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC71/BIOA_UNC71.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_quarantine_guard.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_KRO_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Defense_Sensor_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_70_j_warhead.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_06_aeroculture_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/SND/BIOA_UNC62_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_rachniqueen.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_Placeables_Computer01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_STD_Couch_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_JUG_20_A_Flyby.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_06_control_panel_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/SND/BIOA_UNC62_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_palon.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_HMM_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Krogan/BIOG_KRO_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_40_d_nukeevac.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_05_sniper2_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/LAY/BIOA_UNC62_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_petozi.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_HMN_HGR_BRT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Mobile_Med_Unit_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ice_60f_regiside.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END70_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_06_aeroculture_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/LAY/BIOA_UNC62_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_matriarch.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_HMF_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Military_Maps_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ICE_70_D_Tartakovsky.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END70_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_02_ridge_path_1_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/DSG/BIOA_UNC62_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_medbot.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_HMM_ARM_MASTER_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS50_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Transmtr_Tower_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ice_60d_queen.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END20_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_05_sniper2_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/LAY/BIOA_UNC62_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_julethventralis.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_AVI_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Bench_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ice_60e_freedom.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END70_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_01_ridge_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/DSG/BIOA_UNC62_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_maintenance_door2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_AVI_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Harvester_Egg_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_pro_10_husks_reveal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END70_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO20/pro20_trigger_02_ridge_path_1_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/DSG/BIOA_UNC62_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/EA_HELP_RU.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_ambient_sick_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_ASA_ARM_MRC_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Wall_Safe_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_20_C_Artifact_male.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END70_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_start_kaidan_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/DSG/BIOA_UNC62_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_hanolar.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_ASA_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOG_APL_DOR_BunkerEnt01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_10_H_Spectre_2A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END20_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_start_liara_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/DSG/BIOA_UNC62_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_stgop3.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Localised/ES/Dialog/DLC_Vegas_GlobalTlk_ES.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Locker_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_Pro_10_headscientist_punchout.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END20_10_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_sal_comstore_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/BIOA_UNC62.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_tali.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/VFX/BIOG_v_DLC_Vegas.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/urls.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_END_70_Debris_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_Pro_10_D_Ambush.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END20_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_start_kaidan_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/CIN/BIOA_UNC62_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_stgop1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2_MapApt.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS40_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Waste_Bin_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_10_F_Ashley.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END20_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_sal_captainkirrahe_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/snd/BIOA_UNC61_01_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_stgop2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Localised/ES/BIOA_PRC2_Scoreboard_T_ES.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS40_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_STD_Geth_Tower_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_player_table.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE31/SND/BIOA_FRE31_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/MassEffectConfig.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_sal_comstore_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/snd/BIOA_UNC61_02_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_kaidan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2_CCLava.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS40_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Anti_Tank_Mine_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_10_A_Flyby.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE32/BIOA_FRE32.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_req_officer_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/CIN/BIOA_UNC42_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_liara.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/GUI/Maps/MapPRC2_CCThai.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS40_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Geth_Terminal_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/los/snd_los_end_rover.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE31/DSG/BIOA_FRE31_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/runme.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_sal_captainkirrahe_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/DSG/BIOA_UNC42_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_ashley.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_Crt_Var_ToxicDeath_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS40_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Desk_Computer_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/nor/snd_nor_20d_melding.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE31/LAY/BIOA_FRE31_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/MassEffect.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_noveria_report_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC62/BIOA_UNC62_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_garrus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_Env_FlashingLight_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS40_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Cot_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/los/snd_los_10a_flyby.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE31/BIOA_FRE31_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/wrap_oal.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_req_officer_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC73/BIOA_UNC73_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_aaateam1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_C_Weap__Muzzle_SNP.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Power_Junction_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/los/snd_los_40_j_attack.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE31/DSG/BIOA_FRE31_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/MassEffectLauncher.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_noveria_done_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/BIOA_UNC42_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/jug20_amb_aaateam2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_Crt_ProBeaconAtk_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS30_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_ElevConsole_02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/lav/snd_lav_70_collapse.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_14_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_noveria_report_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC61/BIOA_UNC61_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice70_tartakovsky.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_C_Weap__Muzzle_GTH.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_HUD.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/los/snd_los_10_c_landing.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE31/BIOA_FRE31.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_noveria_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/snd/BIOA_UNC31_02_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/inamorda.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_C_Weap__Muzzle_PST.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS10_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Chair_Bar_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_nukedetonation2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_12_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_noveria_done_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/BIOA_UNC42.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig12_olar_execution.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_C_Weap__Muzzle_ASL.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_STD_Food_Dispenser_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/jug/snd_jug_o_mexecution.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_13_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_leaving_oculon_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/snd/BIOA_UNC31_00_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice70_mira.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_C_Weap__Muzzle_BLS.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_zRAD10_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_20_xeltan.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_10_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_noveria_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/snd/BIOA_UNC31_01_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig10_lab_exit.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_TUR_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Computer_Mon_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_STA_30_Departure.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_11_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_open_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/LAY/BIOA_UNC31_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice60_trig11_lab_sealed.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_V_C_Weap__CoolDown.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Floor_Lamp_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_20_companion.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_report_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/LAY/BIOA_UNC31_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end00_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_StreamingAudioData.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Ammo_Case_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_20_escape.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_done_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/LAY/BIOA_UNC31_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end20_avina.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_TUR_HED_EYE_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Wall_Screen_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_STA_20_A_Arrival.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_open_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/LAY/BIOA_UNC31_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/combat_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_SAL_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/content_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Pro_Terminal_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_STA_20_A_Waking.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/SND/BIOA_END80_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/DSG/BIOA_UNC31_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/creeper.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_Stages_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Table_Bar_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/rom/snd_rom.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE34/LAY/BIOA_FRE34_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_done_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/DSG/BIOA_UNC31_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_turian_garrus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_Placeables_Computers_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/book_closed.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Medical_Bed_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_oculon_approach_dream.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE35/BIOA_FRE35.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig04_airlock_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/BIOA_UNC51.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/codex.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/BIOG_QRN_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/PLC/BIOA_LOS10_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/bookopen.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Table_Large_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_Pro_20_powell_box_move.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE34/DSG/BIOA_FRE34_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/BIOA_UNC51_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_trig_garrus_left_behind.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/snd_bodyfalls_test_PRC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/badge.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Tank_Barricade_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_AL.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE34/DSG/BIOA_FRE34_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig03_callhome_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/SND/BIOA_UNC42_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_trig_wrex.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/snd_prc1_cin_pack.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/blueback.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_STD_Rachni_Hive_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_20_H_Spectre_2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE34/BIOA_FRE34.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig04_airlock_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/SND/BIOA_UNC42_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_quarian_tali.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/codex_dlc.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Gambling_Game_02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_20_I_Spectre_3.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE34/BIOA_FRE34_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig02_4estate_call_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/LAY/BIOA_UNC42_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_trig_garrus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/prc_music_test.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Tire_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_pro_20_e_asari_sovpass.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE33/LAY/BIOA_FRE33_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig03_callhome_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/SND/BIOA_UNC42_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_humanmale_kaidan.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_UI_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Mechanical_Arm_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_20_E_RedShirt.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE33/SND/BIOA_FRE33_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig01_4estate_hackett_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC55/LAY/BIOA_UNC55_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/EA_HELP_POL.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_krogan_wrex.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Animations/BIOA_DLC_UNC52_Bat_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/LAY/BIOA_LOS50_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Desk_and_Chair_02_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_PRO_20_D_Artifact_2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE33/DSG/BIOA_FRE33_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig02_4estate_call_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/LAY/BIOA_UNC42_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_banter_ques.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_Talents_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_GTH_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/pro/snd_Pro_20_E_Asari.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE33/DSG/BIOA_FRE33_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_start_liara_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/LAY/BIOA_UNC51_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_humanfemale_ashley.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_TreasureTables_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/index_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Foot_Locker_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_WAR_30_G_Death_Complete.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE33/BIOA_FRE33.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_trig01_4estate_hackett_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/LAY/BIOA_UNC53_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ashley.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_Movement_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_First_Aid_Stn_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war_30_geth_tower.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE33/BIOA_FRE33_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp121_hackett_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/LAY/BIOA_UNC42_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/cha00_asari_liara.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_Music_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_Bnk_Bunker01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war_20y_flyby2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE32/DSG/BIOA_FRE32_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_ash_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/LAY/BIOA_UNC42_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth_prime.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_GamerProfile_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Tank_Barricade_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_War_30_A_Reveal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE32/LAY/BIOA_FRE32_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-spanish.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp119_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/DSG/BIOA_UNC42_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth_recon_drone.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_Merge_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Couch2_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_WAR_20_Z_Departure.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE32/BIOA_FRE32_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp121_hackett_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/DSG/BIOA_UNC42_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth_destroyer.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_Creatures_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_09_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/r02.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_G_BattlePltfrm_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war_20m_zhou.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE32/DSG/BIOA_FRE32_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp118_distress_call_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/DSG/BIOA_UNC42_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth_juggernaut.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_GalaxyMap_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV60_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/BIOA_GalaxyMap_V_FX_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_war40_armature_reveal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp119_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC42/DSG/BIOA_UNC42_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/PlotManagerAutoDLC_UNC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_07_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/page.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Storage_Locker_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/war/snd_War_20_A_FlyBy.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp111_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/SND/BIOA_UNC51_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth_assault_drone.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/2DAs/BIOG_2DA_UNC_AreaMap_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_08_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/r01.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Demo_Warhead_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_60_q_ambush.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-polish.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp118_distress_call_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/SND/BIOA_UNC51_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_saren2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/BIOA_TEST_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Vehicles/X06_GethShip.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_60_quarian_ambush.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp105_trig01_distress_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/SND/BIOA_UNC51_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/garrus.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/Appearances/Creatures/BIOG_DLC_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/HUD_Holograms.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_60_gambler.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp111_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/SND/BIOA_UNC51_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_final_cutscene.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner04_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_03_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Movers/BIOA_APL_MOV_Lav20Lift01_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_60_garrus_intro.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp103_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/LAY/BIOA_UNC51_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_saren.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/BIOA_PR1_C.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOA_APL_INT_ICE50_MiraBlock_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_STA_30_F_Docking.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp105_trig01_distress_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/SND/BIOA_UNC51_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_council_dead.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner03_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_01_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Target.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_30_krogan.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp102_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/LAY/BIOA_UNC51_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_cutscenes.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner04_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_02_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Locker_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_STA_30_Departure_Fast.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp103_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/LAY/BIOA_UNC51_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_choice.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/dlc_test_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_02_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_VI_News_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/sta/snd_sta_30_escape.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/ART/BIOA_ICE20_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_virmire_report_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/LAY/BIOA_UNC51_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end90_council_alive.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/prc1_human_prisoner03_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_03_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/Gui_CombatHud.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_FC_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/BIOA_ICE00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/sp102_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/LAY/BIOA_UNC51_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end70_elevator.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/dlc_plottest_test_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_VI_Oculon_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_GUI_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/ICE/BIOA_ICE00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig02_c_bodies_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/DSG/BIOA_UNC51_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/end80_banter_01.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/dlc_test_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_01_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOA_LAV70_APL_DOR_FFDoor_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_DP_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE35/DSG/BIOA_FRE35_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig02_d_nihlus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/DSG/BIOA_UNC51_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_hotel_doorman.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/Localised/IT/Soundsets/batarian_ss_IT.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/BIOA_LOS00.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Cup_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_EX_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE35/LAY/BIOA_FRE35_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig02_a_river_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/DSG/BIOA_UNC51_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_investigator.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Dialog/dlc_plottest_test_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/BIOA_LOS00_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/leftarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_WorldInteraction_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_DG_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE35/BIOA_FRE35_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig02_c_bodies_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/DSG/BIOA_UNC51_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_corpguard_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/Localised/DE/Soundsets/batarian_ss_DE.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_08_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA_20_A_Arrival_SEQ03_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_DL_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/FRE/FRE35/DSG/BIOA_FRE35_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_m_scientist02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/CIN/BIOA_UNC51_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_corpguard_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/Localised/FR/Soundsets/batarian_ss_FR.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_09_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_LOS_10_A_Flyby_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_BC_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02D_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_trig02_a_river_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/DSG/BIOA_UNC51_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_business_male_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/snd_prc1_music.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_06_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Containers/TEST_APL_CON_testLocker_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_CB_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02E_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-01.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_headscientist_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/LAY/BIOA_UNC53_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_business_male_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Audio_Content/snd_prc_fusion_torch.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_07_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_InGameGui.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_2P_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02C_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_m_scientist02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/SND/BIOA_UNC53_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_business_female_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_Apartment_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_04_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Guns.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_AM_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02D_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_banter_02_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/LAY/BIOA_UNC53_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_ambient_business_female_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_MAR10_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Shelf_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMF_EX_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02B_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-russian.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_headscientist_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/LAY/BIOA_UNC53_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_amb_interview_human.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Localised/ES/Dialog/DLC_UNC_GlobalTlk_ES.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Lab_Equipment_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMF_WI_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02C_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_banter_01_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/DSG/BIOA_UNC53_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_amb_interview_salarian.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Textures/BIOA_DLC_GalaxyMap_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA90_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMF_CB_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/fws_setup_x64.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_banter_02_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/DSG/BIOA_UNC53_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/human_male_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/Maps/MapUNC52_03.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_TeamHealth.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMF_DL_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_02B_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_banter_00_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/DSG/BIOA_UNC53_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/husk.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/Maps/MapUNC52_04.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/SND/BIOA_LAV70_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_INT_Tool1_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMF_2P_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/Burnout 3 - Takedown (USA).7z' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_banter_01_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/DSG/BIOA_UNC53_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/EA_HELP_PT.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/human_female_2.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/Maps/MapUNC52_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/CIN/BIOA_LOS10_B_Landing_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Bunk_Beds_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMF_AM_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-japanese.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_ash_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/DSG/BIOA_UNC53_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/human_male_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/Maps/MapUNC52_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Prepack_Meal_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Codex.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END20_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/PRO10/pro10_banter_00_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/DSG/BIOA_UNC53_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/geth_stalker.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/GUI_SF_DLC_SaveLoad.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/CIN/BIOA_LOS10_A_Landing_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Bottle_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Music.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END70_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/binkw32log.txt' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_oculon_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC81/BIOA_UNC81_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/human_female_1.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/Maps/MapUNC52_00.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/CIN/BIOA_LOS10_B_Landing_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_VI_Mira_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_VEH_FX_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END80_03_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-brazilian.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp120_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/CIN/BIOA_UNC53_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig08_maeko_dbl_homocide.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Sequences/BIOG_PR1_Q.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/CIN/BIOA_LOS00_Bridge_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_GRN_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_WPN_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END20_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect - Art Book.pdf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_navigator_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/BIOA_UNC53_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig09_maeko_post_garage.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GUI/GUI_SF_DLC_GalaxyMap.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/CIN/BIOA_LOS10_A_Flyby_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/rightarrow.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Tool2_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_TUR_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END80_01_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/xenia_master/xenia.pdb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_oculon_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC54/BIOA_UNC54_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig04_gianna_intercept.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/Faces/BIOA_PR1_FAC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS50_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/search_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Chair_Util_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_TUR_CB_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/CIN/BIOA_END80_01_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect - Prima Official Game Guide.pdf' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_landing_bay_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC51/SND/BIOA_UNC51_05_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig07_garage.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/FaceFX_Assets/BIOG_BAT_FaceFX_Asset.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/CIN/BIOA_LOS00_Bridge_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Pallet_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_SndSetLipAnims.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/xenia_master/xenia.log' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_navigator_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC53/BIOA_UNC53.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_rafaelvargas.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/Batarian/BIOG_BAT_Appr_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS30_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_MASTER_MATERIAL.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_SOV_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_12_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/37 - M4 Part II (Faunts).mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_landing_bay_cutscene_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/LAY/BIOA_UNC21_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_trig02_maeko_greet.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/GameObjects/Characters/Batarian/BIOG_BAT_HGR_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS40_00_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_PartySelect.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_RBT_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/xenia_master/xenia.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_landing_bay_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/LAY/BIOA_UNC21_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_mallenecalis.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/PlotManagerAutoDLC_Vegas.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Fonts.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_SAL_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/35 - From The Wreckage.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_kaiden_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/DSG/BIOA_UNC21_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_opold.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/2DAs/BIOG_2DA_Vegas_AreaMap_X.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Equipment/Weapons/BIOG_WPN_ALL_MASTER_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_NOR_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/36 - The End (Reprise).mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_landing_bay_cutscene_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/DSG/BIOA_UNC21_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_lorikquiin.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_TA_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_06_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_SkillGame.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_PTY_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/dl/xenia_master/LICENSE' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_joker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/DSG/BIOA_UNC21_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_maekomatsuo.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Vampire_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Prepackgd_Meal_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_KRO_CB_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-english.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_kaiden_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/DSG/BIOA_UNC21_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_kairastirling.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Scoreboard_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_04_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Crate_Small_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_NCA_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Redist/fitgirl.md5' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_jenkins_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/BIOA_UNC21.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_lilihierax.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/ART/BIOA_LOS10_05_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Inventory.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_HMM_WI_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_04_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Redist/QuickSFV.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_joker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/CIN/BIOA_UNC21_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_giannaparasini.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS30_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Drink_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Ingame/BIOG_KRO_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Optional Autoloader/readme.txt' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_engineer_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/SND/BIOA_UNC20_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_inamorda.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Scoreboard_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS40_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Fire_Ext_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_80_a_gravity.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-03.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/nor10_jenkins_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/SND/BIOA_UNC20_03_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_anoleis.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_PlatformUI_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS30_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Cont_Tank_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_80_c_uplink.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Optional Autoloader/DLC/DLC_Vegas/AutoLoad.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_trig_garrus_left_behind_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/SND/BIOA_UNC20_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/My_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/ice20_banter_00.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Prefabs.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS30_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Protein_Bar_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_70_c_attack_good.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-french.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_trig_garrus_left_behind_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/SND/BIOA_UNC20_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/attractmovieloc.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_MatFX.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Alarm_Sensor_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_70_sarendead.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Optional Autoloader/DLC/DLC_UNC/AutoLoad.ini' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_quarian_tali_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/LAY/BIOA_UNC20_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/BWLogo.bikx' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Narrative_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/search_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Work_Lamp_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_70_b_relay.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-optional-bonus-videos.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_trig_garrus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/LAY/BIOA_UNC20_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_07.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Loading_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_06a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_UIWorld.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_70_c_attack_evil.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-italian.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_humanfemale_ashley_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/DSG/BIOA_UNC20_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/attractmovie.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Logic_Cap_And_Hold.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/searchweb_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO11_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/x06_music.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END70_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Redist/dxwebsetup.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_quarian_tali_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/LAY/BIOA_UNC20_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_05.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Ahern_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_JUG_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_70_b_control.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END70_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/_Redist/QuickSFV.EXE' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_asari_liara_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/LAY/BIOA_UNC24_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_06.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/BIOA_PRC2_Combat_Logic.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Acid_Land_Mine_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/snd_triggertest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/unins000.exe' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_humanfemale_ashley_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/LAY/BIOA_UNC24_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_03.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_metal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_03a_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA_20_A_Arrival_SEQ02_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/x06_cutscenes_snd.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END70_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-02.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp126_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/LAY/BIOA_UNC24_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_04.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_stone_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Portable_Cots_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/snd_Radio_ON_OFF.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Star Wars Jedi - Fallen Order [FitGirl Repack]/fg-selective-mexican.bin' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_asari_liara_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/LAY/BIOA_UNC24_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_SpaceScenes.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Bar_Table_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/snd_test_tones.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/unins000.dat' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp124_shadow_broker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/DSG/BIOA_UNC24_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/artifact_movie_02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Foot_Imp_Creatures_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOG_APL_DOR_REFStdDoor_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/music_unc.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp126_transmission_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/DSG/BIOA_UNC24_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/VFX/BIOG_V_DLC_UNC52_Env_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_steamDrift.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Geth_Lamp.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/snd_cinematic_amb.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp123_kahoku_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/DSG/BIOA_UNC24_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/EA_HELP_NL.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Packages/Dialog/DLC_Vegas_GlobalTlk.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_FB_CutsceneDOF.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LOS/DSG/BIOA_LOS10_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Lunch_Tray_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/music_bunker.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp124_shadow_broker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/DSG/BIOA_UNC24_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/VFX/BIOG_DLC_Test_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Sky__FarmPlanet.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_VI_Prothean_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/music_knossos.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp120_transmission_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/BIOA_UNC24_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/directx.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/VFX/BIOG_V_DLC_Thrusters_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_smokePlume.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Portable_Stairs_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ice_20_hopper_reveal.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/sp123_kahoku_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/CIN/BIOA_UNC24_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/display_settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/StaticMeshes/BIOA_DLC_UNC52_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_LOS_WaveBreak.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Interactive/BIOG_APL_INT_Gambling_Game_03_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ICE_20_I_Flyby2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_confrontation_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/SND/BIOA_UNC21_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/crash_issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/CookedPC/Packages/Textures/BIOA_DLC_UNC52_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_ScannerLight_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Desk_Lamp_01.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ice_20_a_flyby.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_14_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_empty_locker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/BIOA_UNC24.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/crashes.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_Water_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Sludge_Canister_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ICE_20_H_Arrest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END20_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_citadel_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/LAY/BIOA_UNC21_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_WaterFall_Z_02.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/searchweb_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_UNC_CIN_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/glo/snd_GLO_00_Sovereign.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_13_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_confrontation_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/SND/BIOA_UNC21_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/crash_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/GLO_01_Relay.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_Water_Ramp_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Glasses_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/ice/snd_ICE_10_A_FlybyC.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/DSG/BIOA_END80_13_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_caleston_report_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/LAY/BIOA_UNC25_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/cd_dvd_issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/GLO_Relay_LOAD.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_Water_Twirler_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Physics/BIOG_APL_PHY_Anti_P_Mine_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/glo/snd_glb_00_a_opening_3.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_14_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_citadel_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC21/LAY/BIOA_UNC21_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_90_F_SovereignDead_CUT_05.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_Ocean_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/CIN/BIOA_LAV70_08_CIN_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_WormNeck_Skull_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/glo/snd_glo_00_endgood.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/PLC/BIOA_END20_04_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_caleston_done_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/BIOA_UNC30_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/blue_screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_90_SovereignGood_CUT_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Env_Jug_SideRipples.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Fi/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_JUG_40_Outrun_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/glo/snd_glb_00_a_opening.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_12_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_caleston_report_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/CIN/BIOA_UNC30_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/cd_dvd_issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_90_F_SovereignDead_CUT_03.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/CIN/BIOA_LAV60_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_PHY_Human_Lamp.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/glo/snd_glb_00_a_opening_2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_13_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_caleston_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/SND/BIOA_UNC25_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_90_F_SovereignDead_CUT_04.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_dMetal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/CIN/BIOA_LAV70_08_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_MRC_ARM_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_saren_suicide.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_10_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_caleston_done_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/BIOA_UNC30.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_90_F_SovereignDead_CUT_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_Powers_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_09_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_MRC_HED_PRO_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_sovereign_dead.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_11_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor00_popup_text_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/LAY/BIOA_UNC25_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_90_F_SovereignDead_CUT_02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_TechShield.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_10_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/BIOG_Humanoid_MASTER_MTR_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_90_f_sovereigndead.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_08_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/vorbisfile.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_caleston_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/SND/BIOA_UNC25_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_70_C_Attack_Good_CUT_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_Hack_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_07_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/Asari/BIOG_ASA_HED_PROMorph_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_a_nodeclose.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_09_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/WINUI.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_turian_garrus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/DSG/BIOA_UNC25_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_70_C_Attack_Good_CUT_02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_T_Heal_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/ART/BIOA_LAV70_08_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/EA_Logo_White.GIF' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_RBT_ROB_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_90_c_sovereigngood.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/unrar.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor00_popup_text_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/LAY/BIOA_UNC25_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Updating_your_video_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_70_C_Attack_Evil_CUT_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_TruckJack_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_07_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_RBT_TNK_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Audio_Content/Cutscenes/end/snd_end_90_e_infusion.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_07_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/vorbis.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_trig_garrus_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/DSG/BIOA_UNC25_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/END_70_C_Attack_Evil_CUT_02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Waste_Bin_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_08_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_RBT_DRO_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG70/BIOA_JUG_70_beacon_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/rld.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/cha00_turian_garrus_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/DSG/BIOA_UNC25_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Citadel_Est.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_MineEffects_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_06_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_RBT_HDR_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG70/BIOA_JUG_70_J_Contact_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/unicows.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_joker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/BIOA_UNC25_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/db_standard.bikx' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_ThorianPod.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_07_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_NCA_HAN_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG40/BIOA_JUG_40_C_Nukeversion2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/PhysXCore.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_leaving_oculon_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/CIN/BIOA_UNC25_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/LOS_40_J_Attack_CUT_01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_EmissLightFX_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_05_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_NCA_SOV_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG40/BIOA_JUG_40_D_Nukeevac_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/PhysXLoader.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_ilos_open_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/SND/BIOA_UNC24_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Minimum_requirements.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Mass_Effect_Logo_Movie.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Explosion_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/directional.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_VAR_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG20/BIOA_JUG_20_A_Flyby_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/OpenAL32.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_joker_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC25/BIOA_UNC25.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Monitor.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_15.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Crate_XL_Dest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_04_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/WebHelp_Skin_Files/XP_Silver/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_GTH_HOP_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG40/BIOA_JUG_40_B_Sarenversion2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/END/LAY/BIOA_END80_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/paul.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_ilos_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/SND/bioa_unc24_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/LEFT HAND INDEX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_16.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Drill_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_05_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_THO_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE70/BIOA_ICE_70_E_Benez_Standv2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccspace03_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/NxCooking.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_ilos_open_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC24/SND/BIOA_UNC24_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Manually_starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_13.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Footsteps.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_03_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_TRT_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE70/BIOA_ICE_70_G_Neutron_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccspace_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/ogg.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_ian_ferguson_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/DSG/BIOA_UNC31_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Hard_Drive_space.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_14.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_P_Anti_Tank_Mine_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_03_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-us/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_TCH_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE70/BIOA_ICE_70_A_Crash_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccspace02_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/binkw32.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_ilos_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/DSG/BIOA_UNC31_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Installing_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_11.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_PreRendered/BIOA_V_CIN_END70_Atk_Evil.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Creatures/BIOG_CBT_TEN_NKD_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE70/BIOA_ICE_70_E_Benez_Stand_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccspace02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/MassEffectGDF.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_feros_report_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/BIOA_UNC31_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Gameplay_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_12.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/Cinematics_RealTime/BIOG_V_Cin_Engines.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_GameOver.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE60/BIOA_ICE_60_F_Regicide_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCSpace.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_ian_ferguson_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/CIN/BIOA_UNC31_CIN.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Graphic_corruption.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_09.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Z_TEXTURES_A_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/glossary_n.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA_20_A01_Arrival_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE60/BIOA_ICE_60_Reaction_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccspace02_art.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Binaries/binkw23.dll' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_feros_done_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/snd/BIOA_UNC30_01_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_10.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/VFX_ME_D2.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_SharedAssets.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE60/BIOA_ICE_60_D_Queen_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCSim_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_feros_report_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC31/BIOA_UNC31.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/error_message.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_07.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Weapons_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_06_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Tutorial.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE60/BIOA_ICE_60_E_Freedom_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_feros_approach_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/LAY/BIOA_UNC30_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Emptying_Temporary_Files.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_08.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Z_GLOBAL_A_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV60_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA_20_A_Arrival_SEQ01_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE20/BIOA_ICE_20_I_FlyBy2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim05_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_feros_done_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/snd/BIOA_UNC30_00_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Ending_background_tasks.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_05.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_MG_Imp_Dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_JUG_80_X_Outrun_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/ICE20/ice20_anoleis_NonSpeaking_facefx.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCSim_ART.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_empty_locker_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/LAY/BIOA_UNC30_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Display_Settings.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_06.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Muzzle.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_CombatTest_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS10/BIOA_LOS_10_C_Landing_01_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim04_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR20/nor20_feros_approach_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/LAY/BIOA_UNC30_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/EA_HELP_NO.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_03.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Sand_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Textures/BIOA_CombatTest_T.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/NOR10/BIOA_NOR_10_C_Biotics_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim05_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_watcher_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/DSG/BIOA_UNC30_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Crash_Issues3.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/Jug_70_Beacon_CUT_04.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impacts_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO_20_C_Artifact_male_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS10/BIOA_LOS_10_A_FlyBy_SEQ01_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim03_lay_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS50/los50_conduit_crash_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/LAY/BIOA_UNC30_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/DirectX.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/arcelia.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Dirt_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_06_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Temp/BIOG_APL_STD_Sign_Post.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS10/BIOA_LOS_10_A_FlyBy_SEQ02_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim04_dsg_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_trig_c_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/DSG/BIOA_UNC30_01_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Cleaning_your_CD_DVD.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/ISACT/armature.isb' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Impact_Grass_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV70_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/glossary_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_STA40_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_80_X_Outrun_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim02_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_watcher_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/DSG/BIOA_UNC30_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Crash_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/Movies/DLC_UNC_Ending.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Water_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_04_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/en-uk/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_PRO_10_A_Flyby_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/LOS10/BIOA_LOS_10_A_Flyby_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccsim03_dsg.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_trig_b_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/DSG/BIOA_UNC30_00_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/CD_DVD_Issues2.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_UNC/Movies/DLC_UNC_Opening.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_ShockwaveBase.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_05_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Es/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_ARM_MED_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_Jug_80_R_Wounded_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/bioa_prc2aa_00_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_trig_c_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC30/DSG/BIOA_UNC30_00_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/CD_DVD_Troubleshooting.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/UplinkSEQ01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Ice_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Da/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/StaticMeshes/BIOA_UNC40_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_jug_80_U_nukeactivation_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/BIOA_PRC2AA_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_trig_a_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/SND/BIOA_UNC10_02_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/Blue_Screen_.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/UplinkSEQ02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX/BIOG_V_Veh_Cannon_Imp_Rubber_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_03_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/De/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_ARM_HVY_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_80_J_Warhead_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/bioa_prc2aa_00_dsg_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_trig_b_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC11/BIOA_UNC11.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/CD_DVD_Issues.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/sunset.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/UI/TestUIScenes.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Sv/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Characters/Humanoids/HumanFemale/BIOG_HMF_ARM_LGT_R.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_80_K_SarenEntry_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2AA/bioa_prc2aa_00_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_oculon_attack_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/SND/BIOA_UNC10_00_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Welcome.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/UCW_Loading_Flyby.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/UI/UIArcPackage.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/LAY/BIOA_LAV60_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Cz/index_h.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOG_APL_DOR_REFManDoor_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_80_C_Nukeversion2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai_snd.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_trig_a_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/SND/BIOA_UNC10_01_SND.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/autorun.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/STA_ArrivalSEQ03.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_SnowGusts.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_10_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt-br/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Glass/BIOG_APL_Glass_01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_80_D_Nukeevac_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/CombatPerfTest_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/04 - Battle At Eden Prime.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_watcher_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/LAY/BIOA_UNC10_01_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Video_Card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/STA_ArrivalSEQ04.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/UI/DefaultUISkin.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_11_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Ru/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/BIOG_APL_Invisible_P.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_40_E_Nukedetonation2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCThai_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/05 - Saren.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS40/los40_oculon_attack_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/LAY/BIOA_UNC10_02_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/Warranty.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/STA_ArrivalSEQ01.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_MeshEmitterTest.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_08_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Pol/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Redical.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG80/BIOA_JUG_80_B_Sarenversion2_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/BIOA_PRC2_CCThai_L.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_d_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/LAY/BIOA_UNC10_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/TOP BANNER.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/STA_ArrivalSEQ02.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_Prototype_Glass.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/DSG/BIOA_LAV70_09_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/pt/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Plot/BIOG_ARROW_S.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG70/BIOA_JUG_70_K_Explosion_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai05_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/03 - Eden Prime.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_watcher_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC20/LAY/BIOA_UNC20_00_LAY_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Updating_your_sound_driver.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/PRO_20_E_asariopening.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/TrailBeam.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_00_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/NL/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_Options.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/JUG70/BIOA_JUG_70_O_Mexecution_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai06_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/Bonus Content/Mass Effect OST/02 - The Normandy.mp3' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_bc_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/DSG/BIOA_UNC10_02_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/starting_the_game.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/STA_30_F_docking.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_AndrewsCrustofLiteChoAssUp.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV70_00_PLC_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/No/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_SF_ReplayCharacterSelect.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA30/BIOA_STA_30_F_Docking_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai03_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/LOS30/los30_trig_d_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/LAY/BIOA_UNC10_00_LAY.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Starting_the_installation_manually.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/ME_EAsig_720p_v2_raw.bikx' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Proto__PrefabsTest_Z.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_05_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/Hu/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GameObjects/Placeables/Doors/BIOG_APL_DOR_REFDesDoor01_L.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA60/BIOA_STA_60_Garus_Intro_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai04_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_alien_non_sapient_N.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/DSG/BIOA_UNC10_01_DSG_LOC_int.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/my_game_fails_to_start.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Movies/MEvisionSEQ3.bik' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/BIOG_V_Proto_MatCharacters.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/LAV/PLC/BIOA_LAV60_06_PLC.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/It/go.gif' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/GUI/GUI_Hologram.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Animations/Cinematics/STA30/BIOA_STA_30_Departure_Fast_A.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/DLC/DLC_Vegas/CookedPC/Maps/PRC2/bioa_prc2_ccthai01_lay.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/Dialog/NOR10/codex_citadel_government_D.upk' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Maps/UNC/UNC10/DSG/BIOA_UNC10_02_DSG.SFM' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/docs/EA Help/fr-fr/Sound_card.htm' # bad gid
handle_bad_group_id '/mnt/hdd/gemu/Mass Effect/BioGame/CookedPC/Packages/VFX_Prototype/v_River_Prototype.upk' # bad gid
                                               
                                               
                                               
######### END OF AUTOGENERATED OUTPUT #########
                                               
if [ $PROGRESS_CURR -le $PROGRESS_TOTAL ]; then
    print_progress_prefix                      
    echo "${COL_BLUE}Done!${COL_RESET}"      
fi                                             
                                               
if [ -z $DO_REMOVE ] && [ -z $DO_DRY_RUN ]     
then                                           
  echo "Deleting script " "$0"             
  rm -f '/home/daniel/project/python/xresgrad/v2/rmlint.sh';                                     
fi                                             
