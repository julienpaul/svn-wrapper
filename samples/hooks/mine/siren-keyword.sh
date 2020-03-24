#!/usr/bin/env bash
 
# Force to perform a commit without having to change the file
#  to update SVN keyword Revision, Date,...
#set -x
for ff in global.f90 Doxyfile ; do
   siren_file=$(find $SVN_BRANCH -name ${ff})
   [ ! -z ${siren_file} ] && svn propset dummy 1 ${siren_file}
done

exit 0
