#!/bin/bash

<<'ABOUT_SCRIPT'

### ABOUT THIS SCRIPT ###

Aggie Desktop Jamf Toolbox

Written by Samuel Mosher, Social Sciences IT
The Regents of the University of California, Davis campus. All rights reserved. 

Updated 11/02/2018

### INSTRUCTIONS ON USE ###

The Aggie Desktop Jamf Toolbox is intended to be a one-stop shop for a tech to run some simple Jamf 
scripts, such as enabling FileVault or assigning the computer to a JSS site.

To modify the script to fit your needs:

# ADDING OPTIONS TO TOOLBOX #

- Under "Define the option names in the list" you will specify the friendly names of the options you'd 
like the toolbox to show. For example, opt1="Assign JSS Site to computer" would populate that name in 
the toolbox script as the first option.

To set any new options, simply add an opt#="name of option here" at the end of the list.

- In the "Offer Toolbox Options" section of the script (towards the end) you will create a new option
and update the list to include whichever option number you created in your variables list.

On the line containing options=("$opt1" "$opt2" "$opt3" etc...) add your "$opt#" to the end of the string.

Below the "case $opt in" add a new option using the format below:

"$opt#")
        echo "some description here"
        your_command(s)_here
        break
        ;;

Replace "$opt#" with your new option number. Between ) and break, add your commands. To be helpful,
echo some information about what your command will be doing. Keep it short and sweet.

IF your command is rather extensive, create a function! This will maintain the clarity of the toolbox
portion of the script.

Any step or function which requires the API, include command 'jssAuth' prior to the function command you are calling.
jssAuth calls a function which will prompt your user for admin credentials and is necessary to use the Jamf API.

- For any important headers, there's are special color schemes available! The line before your 'echo' command, use one of the following:

ucdColorScheme - Yellow background, blue text, bold
errorColorScheme - Red background, white text, bold, makes a chime "donk" sound in Terminal

and at the end of your echo text, prior to the final quotation mark, use $(resetColorScheme) 

For example:

ucdColorScheme
echo "### Menu heading here ###$(resetColorScheme)"

You can create a new color scheme using the Function instructions below - add it in with the others.
Use `tput` to manage. A web search of tput color schemes will let you know which numeric values
point to which colors, and other various formatting options you can use.

# CREATING A FUNCTION #

Functions are defined early in the script and then can be used as commands throughout the script
similar to a variable. To create a function:

- Under "Define global functions for options menu" add the following:

functionName() {
  your_script_or_commands_here
}

Example:

printHelloWorld() {
  echo "Hello World!"
}

To call your function, add functionName to the necessary places (except use your function name!)
In the example above, referencing printHelloWorld would say "Hello World!" wherever you called it.

### SCRIPT SUPPORT ###

If you run into any issues using or modifying the script, contact the Aggie Desktop Jamf dev
team via aggiedesktop (at) ucdavis (dot) edu.

ABOUT_SCRIPT

### VARIABLES SECTION ###

# Set terminal window size and color
printf '\e[8;30;90t'

osascript -e "tell application \"Terminal\" to set background color of window 1 to {0,0,0,0}"
osascript -e "tell application \"Terminal\" to set normal text color of window 1 to {0,45000,0,0}"

# Set some global variables

jssUrl=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url | rev | cut -c 2- | rev)
httpStatus=""
httpUnauth="HTTP/1.1 401"
httpAuthOk="HTTP/1.1 200"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
COLUMNS="12"

# Define the option names in the main menu list. If you change these, be sure
# to fix the commands/functions called in the menu portion of the script

opt1="Assign JSS Site to computer"
opt2="Enable FileVault"
opt3="Reissue FileVault Key"
opt4="Fix Mac"
opt5="Update Inventory"
opt6="Assign computer to a patch group"

# Define the option names for patch policies, as defined in BigFix. ANY changes here will require
# you to also update the smart groups in JSS.

patchOpt1="Test"
patchOpt2="Early"
patchOpt3="Workstation"

### FUNCTIONS ###

# The jamfRecon function makes it easier to run a jamf Recon in the script and limits output on the screen.

jamfRecon() {
  sudo jamf recon 2&>1
}

# The jssAuth function collects JSS credentials for connecting to the API and makes sure it can actually connect OK.

jssAuth() {

# Prompt the user to enter their username and password to connect to the JSS API. Username is cleartext, password is secret.
# If either set of credentials is blank, loop until something is provided

if [ "$jssCredentialsSupplied" == "" ]; then
while [ "$httpAuth" != "OK" ]; do
  echo "Please enter your JSS Username. This can be your LDAP credentials."
      if [ "$jssUser" == "" ] ; then
        read -p "Enter your JSS Username: " jssUser
      fi
      read -s -p "Enter the password for user $jssUser: " jssPassword
        if [ "$jssPassword" == "" ]; then
          echo "ERROR: You need to enter a password for $jssUser - try again!!"
            read -s -p "Enter the password for user $jssUser: " jssPassword
        fi
        
        # Tell the toolbox that the user has supplied both a username and password to connect to the API.
        
        jssCredentialsSupplied="yes"

        # Test the API authorization status and make sure you don't get a 401 error as in httpUnauth. If so, try again.
          httpStatus="$(curl -IL -s -u "$jssUser":"$jssPassword" -X GET $jssUrl/JSSResource/jssuser -H "Accept: application/xml" | grep HTTP)" > /dev/null
          if [[ "$httpStatus" == "$httpUnauth"* ]]; then
            echo ""
            errorColorScheme
            echo "API Authorization failed. Please try again.$(resetColorScheme)"
            echo ""

            # Clear broken credentials
              jssUser=""
              jssPassword=""
              
            # If API is successfully called and the HTTP response matches the one in httpAuthOk, then proceed.
            
            elif [[ "$httpStatus" == "$httpAuthOk"* ]]; then
              httpAuth="OK"
              echo ""
              echo "API Authorization succeeded, continuing..."
              echo ""
          fi
      done
    
    # If the user has previously supplied their JSS credentials in this session, re-use those
    
    elif [ "$jssCredentialsSupplied" = "yes" ] && [ "$httpAuth" = "OK" ]; then
      echo "Using credentials previously supplied for JSS user $jssUser..."
  fi
}

# The siteSelect function prompts the user to change the site assigned to the computer in the JSS.

siteSelect() {

# If present, clear site select values from previous loops.

computerSiteModify=""
siteExistContinue=""
siteChoice=""
allSites=""
currentSiteAssignment=""

  echo "Retrieving list of Sites from $jssUrl ..."

  # Get list of all JSS sites and the currently assigned site for the computer, if any, using the API

  allSites="$(curl -s -u "$jssUser":"$jssPassword" -X GET $jssUrl/JSSResource/sites -H "Accept: application/xml" | xpath "/sites/site/name" 2>/dev/null | sed -e 's/<name>//g;s/<\/name>/ /g')"
  currentSiteAssignment="$(curl -s -u "$jssUser":"$jssPassword" -X GET $jssUrl/JSSResource/computers/serialnumber/$serialNumber -H "Accept: application/xml" | xpath "/computer/general/site/name" 2>/dev/null | sed -e 's/<name>//g;s/<\/name>/ /g')"

  # Checks to see if a site assignment already exists.  
  
  if [[ "$currentSiteAssignment" != *"None"* ]]; then

    # Checks to see if the user wants to change the current site.
    # If the user DOES, then siteExistContinue is set to YES (breaks loop) and computerSiteModify is set to 0.
    # The lack of a site ("None" in JSS) will also set computerSiteModify to 0, so yes, please modify!
    
    while [[ $siteExistContinue = "" ]]; do
      echo ""
      ucdColorScheme
      echo "##### EXISTING SITE ASSIGNED!!! ##### $(resetColorScheme)"
      echo ""
      echo "Existing site assigned to system: $currentSiteAssignment"
      echo ""
      echo "Would you like to change the site for $serialNumber?"
        PS3='Please select an option: '
        options=("Yes" "No")
          select opt in "${options[@]}"
          do
            case $opt in
              "Yes")
                  echo "OK, proceeding..."
                  siteExistContinue="Yes"
                  computerSiteModify=0
                  break
                  ;;
              "No")
                  echo "OK, exiting site select tool..."
                  siteExistContinue="No"
                  computerSiteModify=1
                  break
                  ;;
              *) echo invalid option;;
            esac
          done 
    done
  else
    echo ""
    echo "No existing site found for $serialNumber. "
    computerSiteModify=0
  fi
    
  # Check and make sure that the user WANTS to modify the site assignment, if not then exit here.
    
  if [ "$computerSiteModify" != "1" ]; then

    # Prompt user to select site

    echo "Please select a site for computer $serialNumber:"
    echo ""
    PS3='Please select an option: '
    options=(${allSites[@]} "None" "Exit")
    select siteChoice in "${options[@]}";
    do
    
    # Leave the loop if the user says 'cancel'
    case $siteChoice in 
      "Exit")
        echo ""
          echo "Exiting site select tool..."
          computerSiteModify=1
          break
          ;;

      *)
        # Continue if the site exists in the array

      #else
          echo "You selected site $siteChoice. Contacting JSS to submit changes for computer $serialNumber ..."

          # Generate the appropriate XML for API call and PUT it up into JSS

          apiSiteData="$(echo "<computer><general><site><name>$siteChoice</name></site></general></computer>")"
          curl -s -u "$jssUser":"$jssPassword" -X PUT -H "Content-Type: text/xml" -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiSiteData" $jssUrl/JSSResource/computers/serialnumber/$serialNumber > /dev/null
          echo "Done, submitting changes to JSS!"
          echo ""
          
          # Ask the user if they would like to run their site-specific deployent items, if they have a site which does not equal None

          if [ "$siteChoice" != "None" ]; then

            ucdColorScheme
            echo "Would you like to run your site deployment scripts?"
            echo "This process can take a while, depending on the amount of policies that need to be run.$(resetColorScheme)"
              PS3='Please select an option: '
              options=("Yes" "No")
              select opt in "${options[@]}"
              do
                  case $opt in
                      "Yes")
                          echo "OK, running deployment scripts for site $siteChoice..."
                          sudo jamf policy -trigger $siteChoice"_enroll"
                          break
                          ;;
                      "No")
                          echo "OK, exiting select tool..."
                          break
                          ;;
                      *) echo invalid option;;
                  esac
              done
            fi
        break
      esac
    done
  fi
}

# The patchGroup function allows a user to assign a patch group to their system.

patchGroup() {

# If present, clear patch group assignment values from previous loops.

patchAssignmentName=""
patchAssignmentId=""
patchGroupExistContinue=""
patchGroupModify=""

# Check for existing patch group assignment in DeploymentInfo.txt.

echo "Checking for existing Patch Group assignment..."

patchAssignmentExists="$((while read line; do
if [[ $line =~ "AGDT_PatchPolicy"* ]] ; then echo "$line"; fi
done </Library/agdt/DeploymentInfo.txt) | awk '{print $1}')"

patchAssignmentName="$((while read line; do
if [[ $line =~ "AGDT_PatchPolicy"* ]] ; then echo "$line"; fi
done </Library/agdt/DeploymentInfo.txt) | awk '{print $3}')"

# Make sure that if a patch assignment is found, that it matches one of the BigFix patch proup variables or isn't set to null.
# If not, error and exit so we don't write bad data back to BigFix.

if [ "$patchAssignmentExists" != "" ] && [ "$patchAssignmentName" = "" ]; then
  errorColorScheme
      echo " ### FATAL ERROR ### $(resetColorScheme)"
      echo "Patch Group is null, but the framework is there."
      echo "DeploymentInfo likely corrupt or tampered with!"
      echo "These are uncharted waters. Exiting script to prevent issues..."
      exit 1

elif [ "$patchAssignmentExists" != "" ] && [ "$patchAssignmentName" != "" ]; then
    case $patchAssignmentName in
      $patchOpt1)     
      patchAssignmentId=$patchGroup1
      ;;
      $patchOpt2)     
      patchAssignmentId=$patchGroup2
      ;;
      $patchOpt3)     
      patchAssignmentId=$patchGroup3 
      ;;
      * )
      errorColorScheme
      echo " ### FATAL ERROR ### $(resetColorScheme)"
      echo "$patchAssignmentName does not match any patch group."
      echo "DeploymentInfo likely corrupt or tampered with!"
      echo "These are uncharted waters. Exiting script to prevent issues..."
      exit 1
      ;;
  esac

# If a match is found, then run a menu to ask if the user would like to replace the existing patch group membership  

  while [[ $patchGroupExistContinue = "" ]]; do
    echo ""
    ucdColorScheme
    echo "##### EXISTING MEMBERSHIP FOUND!!! ##### $(resetColorScheme)"
    echo ""
    echo "Existing patch group membership found: $patchAssignmentName"
    echo ""
    echo "Would you like to replace the existing group membership?"
      PS3='Please select an option: '
      options=("Yes" "No")
        select opt in "${options[@]}"
        do
          case $opt in
            "Yes")
                echo "OK, proceeding..."
                patchGroupExistContinue="Yes"
                patchGroupModify=0
                break
                ;;
            "No")
                echo "OK, exiting patch group assignment tool..."
                patchGroupExistContinue="No"
                patchGroupModify=1
                break
                ;;
            *) echo invalid option;;
          esac
        done 
  done

# If an existing patch group is found AND the user would like to update the membership, then first 
# delete mention in DeploymentInfo.txt (read by BigFix)

  if [ $patchGroupExistContinue = "Yes" ]; then
    echo "Removing computer from Patch Group $patchAssignmentName..."
    sed -i -e '/AGDT_PatchPolicy.*/d' /Library/agdt/DeploymentInfo.txt
    echo "Computer $serialNumber removed from patch group $patchAssignmentName !" 
    echo ""
    echo "Continuing to patch group assignment tool..."
    sleep 5
  fi

else 
  echo "Existing patch group membership not found. Continuing..."
  echo ""
  patchGroupModify=0
fi

# Run the patch group assignment tool.

# Check to see if the patch group should be modified based on the checks above.
# The options for the menu are defined in the Variables section of the script using patchOpt#.

if [[ $patchGroupModify != 1 ]]; then

echo ""
ucdColorScheme
echo "You are assigning system $serialNumber to a patch policy group."
echo "The three available groups are $patchOpt1 , $patchOpt2 , and $patchOpt3 ."
echo "The options essentially reflect alpha, beta, and production rings in testing patches. $(resetColorScheme)"
echo ""
echo "Which group would you like to assign $serialNumber to?"
PS3='Please select an option: '
options=("$patchOpt1" "$patchOpt2" "$patchOpt3" "Exit")
select opt in "${options[@]}"
do
  case $opt in
    "$patchOpt1")
        echo "OK, assigning $serialNumber to $patchOpt1..."
        echo "AGDT_PatchPolicy = $patchOpt1" >> /Library/agdt/DeploymentInfo.txt
        echo "Done, submitting changes to JSS!"
        break
        ;;
    "$patchOpt2")
        echo "OK, assigning $serialNumber to $patchOpt2..."
        echo "AGDT_PatchPolicy = $patchOpt2" >> /Library/agdt/DeploymentInfo.txt
        echo "Done, submitting changes to JSS!"
        break
        ;;
    "$patchOpt3")
        echo "OK, assigning $serialNumber to $patchOpt3..."
        echo "AGDT_PatchPolicy = $patchOpt3" >> /Library/agdt/DeploymentInfo.txt
        echo "Done, submitting changes to JSS!"
        break
        ;;
    "Exit")
        echo "OK, exiting patch group assignment tool..."
        break
        ;;
    *) echo invalid option;;
  esac
done
else
echo ""
fi
}

# Just some color scheme functions to make things festive. To update or create new, see the 
# instructions section at the top of the script.

ucdColorScheme() {
  tput setaf 4; tput setab 3; tput bold;
}

errorColorScheme() {
  tput setaf 7; tput setab 1; tput bold; tput bel;
}

resetColorScheme() {
  tput sgr 0;
}

# A function to call a proper, similar exit within the script.

exitScript() {
  echo ""
  ucdColorScheme
  echo "OK, exiting Aggie Desktop Jamf Toolbox! $(resetColorScheme)"
  echo ""
  exit 0
}

### THE MENUS ARE BELOW THIS LINE, EXCEPT WHEN DEFINED WITHIN A FUNCTION ###

# Show an intro pane for the script to the user with some branding.

echo ""
clear
ucdColorScheme
echo "#=======================================================================================#"
echo "                                                                                         "
echo "          ___   ______________________   ____  ___________ __ ____________  ____         "
echo "         /   | / ____/ ____/  _/ ____/  / __ \/ ____/ ___// //_/_  __/ __ \/ __ \        "
echo "        / /| |/ / __/ / __ / // __/    / / / / __/  \__ \/ ,<   / / / / / / /_/ /        "
echo "       / ___ / /_/ / /_/ // // /___   / /_/ / /___ ___/ / /| | / / / /_/ / ____/         " 
echo "      /_/  |_\____/\____/___/_____/  /_____/_____//____/_/ |_|/_/  \____/_/              "
echo "                                                                                         "
echo "                                                                                         "
echo "                                      JAMF Toolbox                                       "
echo "                                                                                         "
echo "                                                                                         "
echo "                                       Script v2.0                                       "
echo "     The Regents of the University of California, Davis campus. All rights reserved.     "                  
echo "                                                                                         "
echo "#=======================================================================================#"
resetColorScheme
echo ""

### GENERATE THE AGGIE DESKTOP JAMF TOOLBOX MENUS ### 

# Create larger loop to re-run the menu options until the user explicitly exits.

scriptExit=0
while [[ $scriptExit == 0 ]];
do

# Offer toolbox options.
# REMINDER: Any step or function which requires the API, include function'jssAuth' prior to the function you want to call.
# The options for the menu are stored in the Variables section under opt#.
# Below each option, specify the commands or functions you want to call between the ')' and the 'break'.

echo ""
ucdColorScheme
echo "###  Welcome to the Aggie Desktop JAMF Toolbox. What would you like to do?   ### $(tput sgr 0)"
echo ""
echo "You are currently working with server $jssUrl"
echo ""
PS3='Please select an option: '
options=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "Exit")
select opt in "${options[@]}"
do
  case $opt in
    "$opt1")
        echo "OK, running Site Select utility..."
        echo ""
        jssAuth
        echo ""
        siteSelect
        break
        ;;
    "$opt2")
        echo "OK, enabling FileVault 2..."
        sudo jamf policy -trigger enableFilevault
        break
        ;;
    "$opt3")
        echo "OK, reissuing FileVault key..."
        sudo jamf policy -id 11
        break
        ;;
    "$opt4")
        echo "OK, running Fix My Mac script (rename, clear cache, submit inventory update to JSS..."
        sudo jamf policy -id 23
        break
        ;;
    "$opt5")
        echo "OK, updating inventory..."
        jamfRecon
        break
        ;;
    "$opt6")
        echo "OK, running Patch Policy Assignment utility..."
        echo ""
        patchGroup
        break
        ;;
    Exit)
        exitScript
        ;;
    *) echo invalid option;;
  esac
done

# Ask if the user would like to go back to the main menu. If not, then fully exit the script.
# This runs after a menu item was selected and has finished, in case a tech needs to do more things.

echo ""
echo ""
ucdColorScheme
echo "###   Would you like to return to the main menu?   ### $(resetColorScheme)"
echo ""
PS3='Please select an option: '
options=("Yes" "No")
  select opt in "${options[@]}"
  do
    case $opt in
      "Yes")
          echo "OK, sit tight..."
          echo ""
          break
          ;;
      "No")
          exitScript
          ;;
      *) echo invalid option;;
    esac
done
done
exit 0
