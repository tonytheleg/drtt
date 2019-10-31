#!/bin/bash
################################################################################
# Script Name: drtt (DR Task Tool)                                             #
# Created: 10/20/17                                                            #
# Created By: Antony Natale                                                    #
# Purpose: The DR Task Tool was designed to simplify service restarts and      #
# validation tasks during DR tests. This tool can aid in checking port status  #
# for an application or perform status, starts, stops and restarts on apps.    #
# The tool was made to be universal so that as new apps are added or removed   #
# from DR, the script does not need to be edited.                              #
################################################################################

# TO DO List
# Change to "service" command instead of using init.d files - some services
# don't have start scripts in /etc/init.d (mostly RHEL 7). "service" command
# should still work on RHEL7 as its redirected to use systemctl, test first.

### GLOBAL VARIABLES ###
servername=$1
range=$2
first_host=${range:0:2} # grabs the first double-digit number from range
last_host=${range: -2}  # grabs the second double-digit number from range
service=$3
action=$4
finish_fail=false # If something fails, the finish time wont be accurate
                  # You'll have to grab yourself when set to true

# For simpllicity sakes later, here are some arrays to organize the good servers
# from the bad ones after SSH/DNS connection check testing

# The Good Ones
server_list=()
server_count=0

# The Bad Ones
naughty_list=()
naughty_count=0


### FUNCTIONS ###

port_test ()
{
    # Positional arguments passed to functions not script
    port=$1
    servername=$2
    range=$3
    first_host=${range:0:2} 
    last_host=${range: -2}  

    # Test connectivity first and get a list of good servers
    ssh_test $servername $first_host $last_host
    echo ""
    sleep 1

    # Check ports on all hosts that could be reached after SSH test
    for i in ${server_list[@]}; do
        echo "Checking port $port on $i"
        ssh -q $i netstat -anp | grep $port | grep LISTEN
        echo
    done
    
    # Get start and stop times to update chat for port check tasks
    get_time
    exit 0
} # END OF FUNCTION

ssh_test ()
{
    # Check connectivity by testing port 22 with netcat
    echo -e "\nTesting connectivity to hosts in cluster...\n"
    
    for i in `seq -w $first_host $last_host`; do
        current_host="${servername}${i}"
        nc -z -w3 $current_host 22 &> /dev/null
        result=$?
        if [ $result -ne 0 ]; then  # If connection failed, add to naughty list
            echo "SSH test for $current_host failed...continuing"
            naughty_list[naughty_count]=$current_host
            naughty_count+=1
        else
            echo "SSH test for $current_host complete"
            server_list[server_count]=$current_host # Otherwise add to good list
            server_count+=1
        fi
    done 

    # Check if there are any servers on the naughty list and output
    if [[ -n $naughty_list ]]; then
        echo -e "\nThe following servers could not be reached on port 22, are" \
                "not resolving or are unreachable."
        echo "Please address these manually: "
        echo "${naughty_list[*]}"
        echo -e "\nContinuing with the remainder of servers...\n"
        finish_fail=true # Manual intervention needed - finish time will be off
    fi 
} # END OF FUNCTION

get_time ()
{
    finish_time=$(date +%I:%M)

    # If all went well, grab finish time, otherise you're on your own
    if [ $finish_fail = true ]; then
        echo -e "Process Complete\n"
        echo -e "Start time: $start_time - Finish time: TBD after manual checks\n"
    else
        echo -e "Process Complete\n"
        echo -e "Start time: $start_time - Finish time: $finish_time\n"
    fi
} # END OF FUNCTION


help_screen ()
{
    echo -e "\nUsage: drtt [OPTION] BASE_HOSTNAME RANGE SERVICE ACTION\n"
    echo -e "Options:"
    echo -e "    -p PORT_NUMBER    used to check if PORT_NUMBER is up and listening"
    echo -e "    -h                prints help screen\n"
    echo -e "(SERVICE and ACTION not required for port check)\n"
    echo "Explanation of arguments:"
    echo "    * BASE_HOSTNAME - Host name only (NO NUMBER ex. dlppsmallbizwls)"
    echo "    * RANGE - Number range of hosts in cluster (written as start-finish ex. 01-16) "
    echo "    * SERVICE - Service/Process to perform action on (ex. cwsbMS, bofaaws))"
    echo "    * ACTION - start, stop, restart"
    echo -e "\nExample usage:"
    echo -e "drtt dlppsmallbizwls 01-08 cwsbMS status\n"
    echo  "For port check:"
    echo -e "drtt -p PORT_NUMBER BASE_HOSTNAME RANGE\n"
    exit 1
} # END OF FUNCTION

### MAIN ###

# Grab the start time for chat updates later
start_time=$(date +%I:%M)

# Check if help flag given
if [[ $1 == "-h" ]]; then
    help_screen
fi

# Check minimum args provided and display usage
if [ $# -lt 4 ]; then
    echo -e "\nYou did not provide the correct number of arguments"
    help_screen
fi

# Check for -p option for port check
if [[ $1 == "-p" ]]; then
    port_test $2 $3 $4
fi

# If not performing port check, first test ssh connection to perform actions
ssh_test $servername $first_host $last_host

echo "" # I think I need some space...

# Perform the specified action on the hosts and its servers
for i in ${server_list[@]}; do
    echo "Performing $action on $i"

    # Performs the action in a subshell and grabs the status, assigns to variable
    service_check=$(ssh -q $i service $service $action 2> /dev/null)
                    
    if [ -z "$service_check" ]; then    # If its empty, something went wrong
        echo "$service file could not be found or $action failed." \
             "Please double check and try again."
        finish_fail=true # Manual intervention needed - finish time will be off
        echo "Skipping..."
    else
        echo "$service_check"
    fi
    echo "" # It's not you its me...
done

# Grab the run times for the task for dr chat
get_time $finish_fail
