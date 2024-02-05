#!/bin/bash

# Define the SSH port
PORT=10167

# Global variable to hold the detected OS
DETECTED_OS=""

# Main interface
INTERFACE=""

parse_arguments() {
    # Parse command-line arguments for the -p option
    while getopts "p:" opt; do
        case "${opt}" in
            p)
                PORT=${OPTARG}
                ;;
            \?)
                echo "Invalid option: -${OPTARG}" >&2
                exit 1
                ;;
        esac
    done
}

# Flush existing iptables rules and set default policies
reset_firewall() {
    echo "Resetting firewall rules..."
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
}

# Block all incoming traffic except on the designated SSH port
block_all_incoming() {
    echo "Blocking all incoming traffic except on port $PORT..."
    iptables -P INPUT DROP
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -A INPUT -p icmp -j ACCEPT
}

# Allow outgoing traffic only for connections established through the designated port
allow_outgoing_for_designated_port() {
    echo "Allowing outgoing traffic only for connections established through port $PORT..."
    # Mark packets related to SSH connections
    iptables -t mangle -A OUTPUT -p tcp --sport $PORT -j MARK --set-mark 1
    # Allow marked traffic and essential services
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m mark --mark 1 -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -P OUTPUT DROP  # Drop all other outgoing traffic
}

# Drop all existing connections to ensure a clean state
drop_all_connections() {
    echo "Dropping all existing connections..."
    conntrack -F
}

# Function to detect the current system type
detect_system_type() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DETECTED_OS=$NAME
    elif type lsb_release >/dev/null 2>&1; then
        DETECTED_OS=$(lsb_release -si)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DETECTED_OS=$DISTRIB_ID
    elif [ -f /etc/debian_version ]; then
        DETECTED_OS=Debian
    elif [ -f /etc/SuSe-release ]; then
        DETECTED_OS=SUSE
    elif [ -f /etc/redhat-release ]; then
        DETECTED_OS=CentOS
    else
        echo "OS not detected."
        DETECTED_OS="unknown"
    fi

    # Normalize OS name to lowercase
    DETECTED_OS=$(echo "$DETECTED_OS" | tr '[:upper:]' '[:lower:]')
    echo "Detected OS: $DETECTED_OS"
}

install_gpp_if_missing() {
    case "$DETECTED_OS" in
        ubuntu|debian)
            if ! command -v g++ >/dev/null 2>&1; then
                echo "g++ not found. Installing g++..."
                sudo apt-get update && sudo apt-get install -y g++
            else
                echo "g++ is already installed."
            fi
            ;;
        centos|fedora|redhat)
            if ! command -v g++ >/dev/null 2>&1; then
                echo "g++ not found. Installing g++..."
                sudo yum install -y gcc-c++
            else
                echo "g++ is already installed."
            fi
            ;;
        suse|opensuse*)
            if ! command -v g++ >/dev/null 2>&1; then
                echo "g++ not found. Installing g++..."
                sudo zypper install -y gcc-c++
            else
                echo "g++ is already installed."
            fi
            ;;
        alpine)
            if ! command -v g++ >/dev/null 2>&1; then
                echo "g++ not found. Installing g++..."
                sudo apk add --update g++
            else
                echo "g++ is already installed."
            fi
            ;;
        *)
            if [ "$DETECTED_OS" = "unknown" ]; then
                echo "Unsupported or unknown OS. Cannot install g++."
            else
                echo "g++ is already installed or OS is unsupported for automatic installation."
            fi
            ;;
    esac
}

# Function to install iptables if it is not already installed
install_iptables_if_missing() {
    echo "Checking for iptables on $DETECTED_OS..."

    case "$DETECTED_OS" in
        ubuntu|debian)
            if ! command -v iptables >/dev/null 2>&1; then
                echo "iptables not found. Installing iptables..."
                sudo apt-get update && sudo apt-get install -y iptables
            else
                echo "iptables is already installed."
            fi
            ;;
        centos|fedora|redhat)
            if ! command -v iptables >/dev/null 2>&1; then
                echo "iptables not found. Installing iptables..."
                sudo yum install -y iptables
            else
                echo "iptables is already installed."
            fi
            ;;
        suse|opensuse*)
            if ! command -v iptables >/dev/null 2>&1; then
                echo "iptables not found. Installing iptables..."
                sudo zypper install -y iptables
            else
                echo "iptables is already installed."
            fi
            ;;
        alpine)
            if ! command -v iptables >/dev/null 2>&1; then
                echo "iptables not found. Installing iptables..."
                sudo apk add --update iptables
            else
                echo "iptables is already installed."
            fi
            ;;
        *)
            if [ "$DETECTED_OS" = "unknown" ]; then
                echo "Unsupported or unknown OS. Cannot install iptables automatically."
            else
                echo "iptables installation not required or OS is unsupported for automatic installation."
            fi
            ;;
    esac
}

# Function to install git if it is not already installed
install_git_if_missing() {
    echo "Checking for git on $DETECTED_OS..."

    case "$DETECTED_OS" in
        ubuntu|debian)
            if ! command -v git >/dev/null 2>&1; then
                echo "git not found. Installing git..."
                sudo apt-get update && sudo apt-get install -y git
            else
                echo "git is already installed."
            fi
            ;;
        centos|fedora|redhat)
            if ! command -v git >/dev/null 2>&1; then
                echo "git not found. Installing git..."
                sudo yum install -y git
            else
                echo "git is already installed."
            fi
            ;;
        suse|opensuse*)
            if ! command -v git >/dev/null 2>&1; then
                echo "git not found. Installing git..."
                sudo zypper install -y git
            else
                echo "git is already installed."
            fi
            ;;
        alpine)
            if ! command -v git >/dev/null 2>&1; then
                echo "git not found. Installing git..."
                sudo apk add --update git
            else
                echo "git is already installed."
            fi
            ;;
        *)
            if [ "$DETECTED_OS" = "unknown" ]; then
                echo "Unsupported or unknown OS. Cannot install git automatically."
            else
                echo "git installation not required or OS is unsupported for automatic installation."
            fi
            ;;
    esac
}

# Function to install make if it is not already installed
install_make_if_missing() {
    echo "Checking for make on $DETECTED_OS..."

    case "$DETECTED_OS" in
        ubuntu|debian)
            if ! command -v make >/dev/null 2>&1; then
                echo "make not found. Installing make..."
                sudo apt-get update && sudo apt-get install -y make
            else
                echo "make is already installed."
            fi
            ;;
        centos|fedora|redhat)
            if ! command -v make >/dev/null 2>&1; then
                echo "make not found. Installing make..."
                sudo yum install -y make
            else
                echo "make is already installed."
            fi
            ;;
        suse|opensuse*)
            if ! command -v make >/dev/null 2>&1; then
                echo "make not found. Installing make..."
                sudo zypper install -y make
            else
                echo "make is already installed."
            fi
            ;;
        alpine)
            if ! command -v make >/dev/null 2>&1; then
                echo "make not found. Installing make..."
                sudo apk add --update make
            else
                echo "make is already installed."
            fi
            ;;
        *)
            if [ "$DETECTED_OS" = "unknown" ]; then
                echo "Unsupported or unknown OS. Cannot install make automatically."
            else
                echo "make installation not required or OS is unsupported for automatic installation."
            fi
            ;;
    esac
}

install_conntrack_if_missing() {
    case "$DETECTED_OS" in
        ubuntu|debian)
            if ! command -v conntrack >/dev/null 2>&1; then
                echo "conntrack not found. Installing conntrack..."
                sudo apt-get update && sudo apt-get install -y conntrack
            else
                echo "conntrack is already installed."
            fi
            ;;
        centos|fedora|"red hat")
            if ! command -v conntrack >/dev/null 2>&1; then
                echo "conntrack not found. Installing conntrack..."
                sudo yum install -y conntrack-tools
            else
                echo "conntrack is already installed."
            fi
            ;;
        suse|opensuse*)
            if ! command -v conntrack >/dev/null 2>&1; then
                echo "conntrack not found. Installing conntrack..."
                sudo zypper install -y conntrack-tools
            else
                echo "conntrack is already installed."
            fi
            ;;
        alpine)
            if ! command -v conntrack >/dev/null 2>&1; then
                echo "conntrack not found. Installing conntrack..."
                sudo apk add --update conntrack-tools
            else
                echo "conntrack is already installed."
            fi
            ;;
        *)
            if [ "$DETECTED_OS" = "unknown" ]; then
                echo "Unsupported or unknown OS. Cannot install conntrack."
            else
                echo "conntrack is already installed or OS is unsupported for automatic installation."
            fi
            ;;
    esac
}

detect_main_interface() {
    # Use ip route to find the default route and extract the interface name
    INTERFACE=$(ip route show default 0.0.0.0/0 | awk '{print $5}' | head -n 1)

    if [ -n "$INTERFACE" ]; then
        echo "Main interface detected: $INTERFACE"
    else
        echo "Main interface could not be detected."
        return 1 # Return a non-zero exit status to indicate failure
    fi
}

change_sshd_port_and_restart() {

    # Ensure PORT variable is not empty and is a number
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "Invalid port: $PORT"
        return 1
    fi

    # Call the OS detection function
    detect_system_type

    # Common path for sshd_config
    SSHD_CONFIG_PATH="/etc/ssh/sshd_config"

    # Update sshd_config to listen on the new port
    if [ -f "$SSHD_CONFIG_PATH" ]; then
        # Backup the original sshd_config file
        cp "$SSHD_CONFIG_PATH" "${SSHD_CONFIG_PATH}.bak"

        # Comment out the existing Port line(s) and set the new port
        sed -i 's/^Port /#&/' "$SSHD_CONFIG_PATH"
        echo "Port $PORT" >> "$SSHD_CONFIG_PATH"

        # Restart sshd service based on the detected OS
        case "$DETECTED_OS" in
            ubuntu|debian|alpine)
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl restart sshd
                else
                    service sshd restart
                fi
                ;;
            centos|"red hat"|"red hat enterprise linux"|fedora|suse|"opensuse leap")
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl restart sshd
                else
                    service ssh restart
                fi
                ;;
            *)
                echo "Could not restart sshd on unknown OS: $DETECTED_OS"
                return 1
                ;;
        esac
        echo "sshd has been configured to listen on port $PORT and restarted."
    else
        echo "sshd_config not found."
        return 1
    fi
}

# Main function to apply configurations
main() {

    # Parse the command-line arguments
    parse_arguments "$@"

    detect_system_type

    # Firewall out attackers
    install_iptables_if_missing
    reset_firewall
    block_all_incoming
    echo "Firewalled out attackers"

    # Kill all established connections    
    install_conntrack_if_missing
    drop_all_connections
    echo "Killed all connections"

    # Download packages
    install_gpp_if_missing
    install_make_if_missing
    install_git_if_missing
    echo "Finished downloading all portspoof dependencies"

    # Get portspoof
    cd ~
    mkdir ./.spooky
    cd ./.spooky/
    git clone https://github.com/drk1wi/portspoof.git
    cd ./portspoof
    ./configure
    make
    make install
    echo "Port Spoof installed sucessfully."

    # Enable portspoof
    detect_main_interface
    reset_firewall
    iptables -t nat -A PREROUTING -i $INTERFACE -p tcp -m tcp --dport 1:$PORT,$PORT:65535 -j REDIRECT --to-ports 4444
    block_all_incoming
    drop_all_connections
    portspoof -c ./tools/portspoof.conf -s ./tools/portspoof.conf -D
    echo "Successfully enabled Port Spoof."

    # Prevent all outgoing connections except for out special port
    allow_outgoing_for_designated_port
    drop_all_connections
    echo "Network configurations applied successfully."

    # Start SSH on new Port
    change_sshd_port_and_restart
}

# Execute main function with root privileges
main "$@"