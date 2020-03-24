#!/usr/bin/env bash

echo -e "\n# Release $(date "+%F") {#rev_$(date "+%F")}" > LOGMSG
msg=false
# get message
POSITIONAL=()
while [[ $# -gt 0 ]]
do
   key="$1"

   case $key in
      -F)
         cat "$2" >> LOGMSG
         shift # past argument
         shift # past value
         msg=true
         break
         ;;
      -m)
         echo "$2" >> LOGMSG
         shift # past argument
         shift # past argument
         msg=true
         break
         ;;
      *)    # unknown option
         POSITIONAL+=("$1") # save it in an array for later
         shift # past argument
         ;;
   esac
done

if $msg ; then

   # add second '#' at the beginning of some line (markdown)
   sed -i 's/^\(# New features\)$/#\1/' LOGMSG
   sed -i 's/^\(# Changes\)$/#\1/' LOGMSG
   sed -i 's/^\(# Bug fixes\)$/#\1/' LOGMSG

   # add '-' at the beginning of some line (markdown)
   sed -i '/^A/ s/^/- /' LOGMSG
   sed -i '/^M/ s/^/- /' LOGMSG
   sed -i '/^MM/ s/^/- /' LOGMSG

   # replace multi space by single space
   sed -i 's/\s\+/ /g' LOGMSG

   # add newline after ':'
   sed -i 's/:/:\n/g' LOGMSG
 
   # remove empty line
   sed -i '/^[[:space:]]*$/d' LOGMSG

   # add '\t-' for other line
   sed -i '/^[-#@]/! s/^/\t-/g' LOGMSG
 
   # add empty line, as first line
   sed -i "1 s/^\(.*\)$/\n\1/" LOGMSG

   # add log message to change log (if not empty)
   # get siren_changelog file
   echo "find $SVN_BRANCHE -name 5_changeLog.md"
   siren_changelog=$(find $SVN_BRANCHE -name 5_changeLog.md)
   echo "siren_changelog : $siren_changelog"
   if [ ! -z ${siren_changelog} ] ; then
      echo "sed -i "/@tableofcontents/r LOGMSG" ${siren_changelog}"
      sed -i "/@tableofcontents/r LOGMSG" ${siren_changelog}
   fi

fi
rm -f LOGMSG

exit 0
