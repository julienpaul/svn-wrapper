#!/usr/bin/env bash

set -e
#set -x

#
# Global check to terminal or file operation
#
if [ -t 1 ]; then
    export IS_TERMINAL=1
else
    export IS_TERMINAL=0
fi

#
# Setup local var
#
HERE=$(pwd)
export GREP=$(which grep)

#
# Setup real svn
#
ME=$(realpath -sm $0)
export SVN=$(which -a svn | $GREP -v "\\$ME" | head -n1)

#
# Setup SVN wrapper directory
#
export SVN_WRAPPER=$(dirname $ME)

#
# Setup SVN root directory
#
_svn_root()
{
   # if the current folder is not under svn revision control, nothing is output          
   # and a non-zero exit value is given                                                  
   if $(\svn info &> /dev/null) ; then                                                   
      # current folder is under svn revision                                             
      if [[ $(\svn --version --quiet | cut -d'.' -f1-2) > 1.6 ]] ; then                  
         # svn 1.7 or upper :                                                            
         #  .svn directory only in SVN_ROOT directory                                    
         echo $(env LANG=C $SVN info | $GREP 'Root Path:' | awk -F: '{print $2}' | xargs)
      else                                                                               
         # svn 1.6 or lower :                                                            
         #  .svn directories in all subdirectories of SVN tree                           
         
         # this command outputs the top-most parent of                                   
         # the current folder that is still                                                                                                                                     
         # under svn revision control to standard out                                    
         
         parent=""                                                                       
         grandparent="."                                                                 
         
         while [ -d "$grandparent/.svn" ]; do                                            
            parent=$grandparent                                                          
            grandparent="$parent/.."                                                     
         done                                                                            
         
         if [ ! -z "$parent" ]; then                                                     
            echo $(readlink -m "$parent")                                                
         else                                                                            
            exit 1                                                                       
         fi                                                                              
      fi                                                                                 
   else                                                                                  
      exit 1                                                                            
   fi        
}
#
export SVN_ROOT=$(_svn_root)

#
# Setup SVN repository root path
#
export SVN_REPO_ROOT=$(env LANG=C $SVN info | $GREP 'Repository Root:' | awk '{print $3}' | xargs)
#
# Setup SVN repository url
#
export SVN_URL=$(env LANG=C $SVN info | $GREP 'URL:' | awk '{print $2}' | xargs)
#
# Setup SVN revision
#
export SVN_REV=$(env LANG=C $SVN info | $GREP 'Revision:' | awk '{print $2}' | xargs)

#
# Setup SVN repository branch path
#
_svn_branche()
{
   text=$HERE
   list="branches branche branch trunk tag tags"
   # add upper case to list
   list="$list $(echo "$list" | tr '[:lower:]' '[:upper:]')"
   for search in $list ; do
      # look for 'search' element in path
      if $(echo $text | grep -q "/$search/") ; then
         # 'prefix' contain path until 'search' element (not include)
         prefix=${text%%$search*}
         # add 2 subdirectories to get the path we looking for
         n=$(( $(echo $prefix | tr -dc / | wc -c) + 2))
         echo $text | cut -d"/" -f1-$n
         exit 0
      fi
   done
   # if no list element in path, keep it
   echo $text
}
SVN_BRANCHE=$(_svn_branche)

#
# Hook dirs
#
[ -z $SVN_ROOT ] && export HOOK_DIR="${HERE}/$3/.svn/hooks" || export HOOK_DIR="$SVN_ROOT/.svn/hooks"

#
# PAGER like git
#
SVN_PAGER="less -FRSX"

#
# Action arguments
#
declare -a ACT_ARGS
declare -a CMD_LINE

#
# Helpers
#

svn_info_field()
{
    local field="$1"
    env LANG=C $SVN info | $GREP "^$field:" | sed "s|^$field: ||"
}

run_hook()
{
    local hook="$1"
    shift
    test -x "$HOOK_DIR/$hook" && "$HOOK_DIR/$hook" "$action" "$@" || true
}

run_hooks()
{
    local hook_type="$1"
    local action="$2"
    local status="$3"
    shift 2

    case "$action" in
    up|update)
        run_hook "$hook_type-update" "$@"
    ;;
    ci|commit)
        run_hook "$hook_type-commit" "$@"
    ;;
    co|checkout)
        run_hook "$hook_type-checkout" "$@"
    ;;
    switch)
        #set -x
        # Collect branches
        if [ x"$hook_type" = x"post" -a x"$status"  = x"0" ]; then
            local svn_branch
            for arg in $CMD_LINE
            do
                if [ ${arg:0:1} != "-" ]; then
                    svn_branch=${arg}
                    break
                fi
            done
 
            if [ -n "${svn_branch}" ]; then
                local current_branch=$(svn_info_field 'Relative URL')
                local svn_repo_hash=$(sha256sum <<< "$SVN_REPO_ROOT" | awk '{print $1}')
                local branches_file="$HOME/.subversion/branches-${svn_repo_hash}.txt"
 
                [ -f "${branches_file}" ] && cp "${branches_file}" "${branches_file}.tmp"
                echo "${current_brach}" >> "${branches_file}.tmp"
                echo "${svn_branch}" >> "${branches_file}.tmp"
                cat "${branches_file}.tmp" | $GREP -v '^$' | sort | uniq > "${branches_file}"
                rm "${branches_file}.tmp"
            fi
        fi
        #set +x
    ;;
    *)
        run_hook "$hook_type-action" "$action" "$@"
    ;;
    esac
}

svn_list_branches()
{
    local svn_repo_hash=$(sha256sum <<< "$SVN_REPO_ROOT" | awk '{print $1}')
    local branches_file="$HOME/.subversion/branches-${svn_repo_hash}.txt"
    
    [ -f "${branches_file}" ] && cat "${branches_file}"
}

modify_args()
{
    local action="$1"
    shift

    local help_mode=0
    local arg
    for arg in "$@"
    do
        case "$arg" in
            --help)
                return 0
            ;;
        esac
    done

    case "$action" in
        st|stat|status)
            ACT_ARGS[${#ACT_ARGS[*]}]="--ignore-externals"
        ;;
        diff)
            local ext
            # Skip spaces changes only for terminal output
            [ $IS_TERMINAL -eq 1 ] && ext="bpu" || ext="pu"
            ACT_ARGS=( "${ACT_ARGS[@]}" "-x" "-$ext" "--internal-diff" )
        ;;
    esac
}

# Filter SVN output. Helps to implement "local ignores"
#set -x
svn_output_colorer()
{
    local CMD="$1"
    if [ -t 1 ]; then
        (
            case $CMD in
                diff|di)
                    (which colordiff > /dev/null 2>&1 && colordiff --color=auto || cat)
                ;;
                log)
                    sed -e 's/^\(.*\)|\(.*\)| \(.*\) \(.*\):[0-9]\{2\} \(.*\) (\(...\).*) |\(.*\)$/\o33\[1;32m\1\o33[0m|\o33\[1;34m\2\o33[0m| \o33\[1;35m\3 \4 (\6, \5)\o33[0m |\7/'
                ;;
                *)
                    (which svn-color-filter.py > /dev/null 2>&1 && svn-color-filter.py $CMD || cat)
                ;;
            esac
        ) | $SVN_PAGER
    else
        cat
    fi
}

svn_output_filter()
{
    local action=$1
    shift

    case "$action" in
        st|stat|status)
            local IGNORES_IN="$SVN_ROOT/.svn/ignores.txt"
            local IGNORES=`mktemp /tmp/XXXXXXXX`

            (
            if [ -f "$IGNORES_IN" ]; then
                cat "$IGNORES_IN" | $GREP -v '^$' | $GREP -v '^#' > "$IGNORES"

                REAL_PATH="n"
                if which realpath > /dev/null; then
                    REAL_PATH="y"
                fi

                while IFS='' read line;
                do
                    # First 8 columns uses for svn status info: 7 info + 1 for space
                    # see `svn help st`
                    type=`echo $line | cut -c 1-2`
                    # Strip trailing space.
                    type="${type%% }"
                    fn=`echo $line | cut -c 9-`
                    # Process only untracked files
                    if [ "$type" = "?" ]; then
                        if [ "$REAL_PATH" = "y" ]; then
                            #set -x
                            fn=`realpath -m --relative-to="$SVN_ROOT" -s -q "$fn"`
                            #set +x
                        fi
                        echo $fn | $GREP -f "$IGNORES" > /dev/null || echo "$line"
                    else
                        echo "$line"
                    fi
                done
            else
                cat
            fi
            ) | svn_output_colorer status

            rm -f "$IGNORES"
        ;;
        diff|log|remove|add|help)
            svn_output_colorer $action
        ;;
        *)
            # Default bypass filter
            cat
        ;;
    esac
}

#
# SVN action
#
action="$1"

echo -e "\nSVN            : $SVN"
echo -e "SVN_WRAPPER    : $SVN_WRAPPER"
echo -e "SVN_ROOT       : $SVN_ROOT"
echo -e "SVN_BRANCHE    : $SVN_BRANCHE"
echo -e "SVN_REPO_ROOT  : $SVN_REPO_ROOT"
echo -e "SVN_REPO_URL   : $SVN_URL"
echo -e "HOOK_DIR       : $HOOK_DIR\n"
echo -e "Revision       : $SVN_REV\n"
#
# Pre-hooks
#
run_hooks pre "$action" 0 "$@"
#
# Modifty command line
#
# disable halting on error
set +e

[ -n "$1" ] && shift
modify_args "$action" "$@"

CMD_LINE=( "${CMD_LINE[@]}" "$@" )
#declare -p CMD_LINE

#
# Real SVN call
#

# detects svn-internal commands
non_internal=`LANG=C $SVN help "$action" 2>&1 | $GREP ': unknown command'`
non_external=`which "svn-$action" 2>/dev/null`
if [ -z "$non_internal" -o -z "$non_external" ]; then
    if [ -z "$non_internal" ]; then
        case "$action" in
            merge|co|checkout|cp|copy|ci|commit|switch|info|propedit|cleanup)
                $SVN $action "${ACT_ARGS[@]}" "$@"
                svn_status=$?
            ;;
            *)
                $SVN $action "${ACT_ARGS[@]}" "$@" | svn_output_filter "$action"
                svn_status=$?
            ;;
        esac
    else
        case "$action" in
            branch|br)
                svn_list_branches
                svn_status=$?
            ;;
            *)
                $SVN $action "${ACT_ARGS[@]}" "$@"
                svn_status=$?
            ;;
        esac
    fi
else
    "svn-$action" "$@" "${ACT_ARGS[@]}"
    svn_status=$?
fi

# enable halting on error
set -e

#
# Post-hooks
#
run_hooks post "$action" $svn_status

exit $svn_status

