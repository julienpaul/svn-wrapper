#!/usr/bin/env bash

# get message
POSITIONAL=()
while [[ $# -gt 0 ]]
do
   key="$1"

   case $key in
      -F)
         LOGMSG=$(cat "$2")
         shift # past argument
         shift # past value
         ;;
      -m)
         LOGMSG="$2"
         shift # past argument
         shift # past value
         ;;
      *)    # unknown option
         POSITIONAL+=("$1") # save it in an array for later
         shift # past argument
         ;;
   esac
done

# Checks whether the commit message is not empty
LOOKOK=1
echo $LOGMSG | \
grep "[a-zA-Z0-9]" > /dev/null || LOOKOK=0  
if [ $LOOKOK = 0 ]; then  

   echo "Empty log messages are not allowed. Please provide a proper log message." >&2  
   echo -e " to continue anyway, press : ENTER"
   echo -e " to cancel         , press : CTRL C"
   read

else

   # Checks whether the commit message consists of at least 8 characters
   # Comments should have more than 8 characters  
   LENMSG=$(echo $LOGMSG | grep [a-zA-Z0-9] | wc -c)  
   
   if [ "$LENMSG" -lt 8 ]; then  
      echo -e "Log messages : $LOGMSG\n"
      echo -e "Please provide a meaningful comment when committing changes." 1>&2  
      exit 1  
   fi

fi  
#echo "Log messages allowed : $LOGMSG"
