import sys
import subprocess
import re

def run_nmap_scan(target_network):
    # Run the Nmap discovery scan
    command = ["nmap", "-sn", target_network]
    result = subprocess.run(command, capture_output=True, text=True)

    # Check if the command was successful
    if result.returncode != 0:
        print(f"Error running Nmap scan: {result.stderr}")
        return

    # Extract live IP addresses from the Nmap output
    live_ips = re.findall(r'Nmap scan report for (\d+\.\d+\.\d+\.\d+)', result.stdout)

    # Sort the live IP addresses in descending order
    live_ips.sort(key=lambda ip: list(map(int, ip.split('.'))))

    # Save the live IP addresses to a text file
    live_ips_filename = f"{target_network.replace('/', '-')}.txt"
    with open(live_ips_filename, 'w') as file:
        for ip in live_ips:
            file.write(f"{ip}\n")

    # Save the raw Nmap output to a separate text file
    raw_output_filename = f"nmap-output-{target_network.replace('/', '-')}.txt"
    with open(raw_output_filename, 'w') as file:
        file.write("Raw Nmap Output:\n")
        file.write(result.stdout)

    print(f"Live IP addresses saved to {live_ips_filename}")
    print(f"Raw Nmap output saved to {raw_output_filename}")

if __name__ == "__main__":
    # Check if the correct number of arguments is provided
    if len(sys.argv) != 2:
        print("Usage: python script.py <target_network>")
        sys.exit(1)

    # Get the target network from the command-line argument
    target_network = sys.argv[1]
    run_nmap_scan(target_network)
