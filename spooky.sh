#!/bin/bash

# Define the SSH port
PORT=252
PORTSPOOF_PORT=4444

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

save_iptables_rules() {
    local filename="$1"
    if [ -z "$filename" ]; then
        echo "Error: Filename is required."
        return 1
    fi

    if ! sudo iptables-save | sudo tee "$filename" > /dev/null; then
        echo "Error: Failed to save iptables rules to '$filename'."
        return 2
    else
        echo "Iptables rules have been successfully saved to '$filename'."
    fi
}

restore_iptables_rules() {
    # Define the filename from which the iptables rules will be restored.
    local filename="$1"

    # Check if the filename is provided.
    if [ -z "$filename" ]; then
        echo "Error: Filename is required."
        return 1
    fi

    # Check if the file exists.
    if [ ! -f "$filename" ]; then
        echo "Error: File '$filename' does not exist."
        return 2
    fi

    # Use iptables-restore to load the iptables rules from the specified file.
    if sudo iptables-restore < "$filename"; then
        echo "Iptables rules have been successfully restored from '$filename'."
    else
        echo "Error: Failed to restore iptables rules from '$filename'."
        return 3
    fi
}

# Flush existing iptables rules and set default policies
reset_firewall() {
    echo "Resetting firewall rules..."

    # Attempt to flush and reset iptables rules, capturing any errors
    if ! iptables -F || ! iptables -X || \
       ! iptables -t nat -F || ! iptables -t nat -X || \
       ! iptables -t mangle -F || ! iptables -t mangle -X || \
       ! iptables -P INPUT ACCEPT || ! iptables -P FORWARD ACCEPT || ! iptables -P OUTPUT ACCEPT; then
        echo "Error occurred while resetting firewall rules."
        return 1 # Indicate failure
    fi

    echo "Firewall rules have been reset successfully."
}

block_all_incoming() {
    echo "Blocking all incoming traffic except on port $PORT..."

    # Apply iptables rules, checking the success of each command
    if ! iptables -P INPUT DROP || \
       ! iptables -A INPUT -i lo -j ACCEPT || \
       ! iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT || \
       ! iptables -A INPUT -p tcp --dport "$PORTSPOOF_PORT" -j ACCEPT || \
       ! iptables -A INPUT -p udp --dport "$PORTSPOOF_PORT" -j ACCEPT || \
       ! iptables -A INPUT -p icmp -j ACCEPT; then
        echo "Error occurred while setting up iptables rules."
        return 1 # Indicate failure
    fi

    echo "All incoming traffic except on designated ports has been blocked successfully."
}

portspoof_all_iptables_rules() {
    echo "Enabling portspoof iptables rules..."

    # Apply iptables rules, checking the success of each command
    if ! iptables -t nat -A PREROUTING -i "$INTERFACE" -p tcp -m tcp --dport 1:$((PORT-1)) -j REDIRECT --to-ports 4444 || \
       ! iptables -t nat -A PREROUTING -i "$INTERFACE" -p tcp -m tcp --dport $((PORT+1)):65535 -j REDIRECT --to-ports 4444; then
        echo "Error occurred while setting up portspoof iptables rules."
        return 1 # Indicate failure
    fi

    echo "Portspoof iptables rules have been enabled successfully."
}

# Block all outgoing traffic except traffic to package managers
block_outgoing_ex_pkgs() {
    echo "Configuring outgoing firewall rules to allow only package management traffic..."

    # Apply iptables rules, checking the success of each command
    if ! iptables -F OUTPUT || \
       ! iptables -P OUTPUT DROP || \
       ! iptables -A OUTPUT -o lo -j ACCEPT || \
       ! iptables -A OUTPUT -p udp --dport 53 -j ACCEPT || \
       ! iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT || \
       ! iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT || \
       ! iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT || \
       ! iptables -A OUTPUT -m state --state RELATED -j ACCEPT; then
        echo "Error occurred while setting up outgoing iptables rules."
        return 1 # Indicate failure
    fi

    echo "Outgoing rules configured successfully to allow package updates and essential services."
}


# Allow outgoing traffic only for connections established through the designated port
block_outgoing_ex_designated() {
    echo "Allowing outgoing traffic only for connections established through port $PORT..."

    # Mark packets related to SSH connections
    # TODO: Add outgoing to local network machines to ports 22 and 3389
    # iptables -I OUTPUT 1 -d 10.100.19.4 -j ACCEPT
    if ! iptables -t mangle -A OUTPUT -p tcp --sport "$PORT" -j MARK --set-mark 1 || \
       ! iptables -t mangle -A OUTPUT -p tcp --sport "$PORTSPOOF_PORT" -j MARK --set-mark 1 || \
       ! iptables -t mangle -A OUTPUT -p udp --sport "$PORTSPOOF_PORT" -j MARK --set-mark 1; then
        echo "Error occurred while marking outgoing packets."
        return 1 # Indicate failure
    fi

    # Allow marked traffic and essential services
    if ! iptables -A OUTPUT -m conntrack --ctstate RELATED -j ACCEPT || \
       ! iptables -A OUTPUT -m mark --mark 1 -j ACCEPT || \
       ! iptables -A OUTPUT -o lo -j ACCEPT || \
       ! iptables -P OUTPUT DROP; then
        echo "Error occurred while setting up outgoing iptables rules."
        return 1 # Indicate failure
    fi
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
        return 1
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
                return 1
            else
                echo "g++ is already installed or OS is unsupported for automatic installation."
                return 1
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
                return 1
            else
                echo "git installation not required or OS is unsupported for automatic installation."
                return 1
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
                return 1
            else
                echo "make installation not required or OS is unsupported for automatic installation."
                return 1
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
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "Invalid port: $PORT"
        return 1
    fi

    detect_system_type

    local SSHD_CONFIG_PATH="/etc/ssh/sshd_config"
    if [ -f "$SSHD_CONFIG_PATH" ]; then
        cp "$SSHD_CONFIG_PATH" "${SSHD_CONFIG_PATH}.bak"
        sed -i 's/^Port /#&/' "$SSHD_CONFIG_PATH"
        echo "Port $PORT" >> "$SSHD_CONFIG_PATH"

        case "$DETECTED_OS" in
            ubuntu|debian|alpine)
                if ! (sudo systemctl restart sshd || sudo service sshd restart); then
                    echo "Failed to restart sshd."
                    return 1
                fi
                ;;
            centos|"red hat"|"red hat enterprise linux"|fedora|suse|"opensuse leap")
                if ! (sudo systemctl restart sshd || sudo service ssh restart); then
                    echo "Failed to restart sshd."
                    return 1
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

    # =================( Parse command-line arguments )=================
    parse_arguments "$@"


    # =================( Detect system type )=================
    if ! detect_system_type; then
        echo "Error: Failed to detect system type."
        return 1
    fi

    # Prevent interactive service restart
    sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf

    # ===========( Create working directory )==========
    WORKING_DIR="$(pwd)/.spooky"

    if ! mkdir -p "$WORKING_DIR"; then
        echo "Error: Failed to create working directory."
        return 1
    fi

    if ! cd "$WORKING_DIR"; then
        echo "Error: Failed to change to working directory."
        return 1
    fi

    # ===========( Save iptables configuration )==========
    OLD_IPTABLES_RULES="$(pwd)/old_iptables_rules"

    if ! install_iptables_if_missing; then
        echo "Error: Failed to install iptables."
        return 1
    fi

    if ! save_iptables_rules "$OLD_IPTABLES_RULES"; then
        echo "Error: Failed to save iptables rules."
        return 1
    fi

    # ==========( Firewall out attackers )==========
    if ! reset_firewall; then
        echo "Error: Failed to reset firewall."
        return 1
    fi

    if ! block_all_incoming; then
        echo "Error: Failed to block all incoming traffic."
        return 1
    fi
    
    if ! block_outgoing_ex_pkgs; then
        echo "Error: Failed to block all outgoing traffic except traffic to package managers."
        return 1
    fi

    echo "Firewalled out attackers"

    # ==========( Download packages )===========
    if ! install_gpp_if_missing; then
        echo "Error: Failed to install g++."
        return 1
    fi

    if ! install_make_if_missing; then
        echo "Error: Failed to install make."
        return 1
    fi

    if ! install_git_if_missing; then
        echo "Error: Failed to install git."
        return 1
    fi

    echo "Finished downloading all portspoof dependencies"

    # ==========( Install portspoof )===========
    if ! git clone "https://github.com/drk1wi/portspoof.git"; then
        echo "Error: Failed to clone portspoof repository."
        return 1
    fi

    if ! cd ./portspoof; then
        echo "Error: Failed to change to portspoof directory."
        return 1
    fi

    if ! ./configure; then
        echo "Error: Failed to configure portspoof."
        return 1
    fi

    if ! make; then
        echo "Error: Failed to make portspoof."
        return 1
    fi

    if ! make install; then
        echo "Error: Failed to install portspoof."
        return 1
    fi

    echo "Port Spoof installed sucessfully."

    # ==========( Enable portspoof )===========
    if ! detect_main_interface; then
        echo "Error: Failed to detect main interface."
        return 1
    fi

    if ! reset_firewall; then
        echo "Error: Failed to reset firewall."
        return 1
    fi

    if ! block_all_incoming; then
        echo "Error: Failed to block all incoming traffic."
        return 1
    fi

    if ! portspoof_all_iptables_rules; then
        echo "Error: Failed to enable portspoof iptables rules."
        return 1
    fi

    # =================(  Re-enable outgoing firewall )=================
    if ! block_outgoing_ex_designated; then
        echo "Error: Failed to block all outgoing traffic except traffic to package managers."
        return 1
    fi

    # =================( Create OpenSSH only signature file )=================
    OPENSSH_SIGS_FILE="$(pwd)/tools/openssh_signatures"
    if ! grep "OpenSSH" "$(pwd)/tools/portspoof_signatures" > "$OPENSSH_SIGS_FILE"; then
        echo "Error: Failed to create OpenSSH signatures file."
        return 1
    fi

    # =================( Start portspoof )=================
    if ! portspoof -c ./tools/portspoof.conf -s "$OPENSSH_SIGS_FILE" -D; then
        echo "Error: Failed to start portspoof."
        return 1
    fi

    echo "Successfully enabled Port Spoof."

    # =================( Change SSH port )=================
    if ! change_sshd_port_and_restart; then
        echo "Error: Failed to change SSH port."
        return 1
    fi
}

# Execute main function with root privileges
if ! main "$@"; then
    echo "An error occurred. Exiting."
    restore_iptables_rules "$OLD_IPTABLES_RULES"
    exit 1
fi