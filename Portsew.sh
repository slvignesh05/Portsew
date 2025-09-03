#!/bin/bash

# Usage: ./vuln_scan_parallel.sh targets.txt

INPUT_FILE="$1"
OUTPUT_DIR="scan_results"
THREADS=5  # Adjust parallel scans
MISCONFIG_PORTS=(21 22 23 25 80 110 143 445 3306 3389 5432 5900 8080 9200 27017)

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: $0 <ip_list_file>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

scan_ip() {
    ip=$1
    OUTFILE="$OUTPUT_DIR/$ip.txt"
    echo -e "\n[*] Scanning $ip..."
    echo "=== Scan Report for $ip ===" > "$OUTFILE"

    # Nmap: Detect open ports
    open_ports=$(nmap -sV -Pn --open -T4 --top-ports 1000 "$ip" | \
                 tee -a "$OUTFILE" | grep -E '^[0-9]+/tcp' | awk '{print $1}' | cut -d'/' -f1)

    if [[ -z "$open_ports" ]]; then
        echo "No open ports found." | tee -a "$OUTFILE"
        return
    fi

    echo "Open ports: $open_ports" | tee -a "$OUTFILE"

    # Misconfigured ports
    for port in $open_ports; do
        if [[ " ${MISCONFIG_PORTS[*]} " == *" $port "* ]]; then
            echo "⚠️  Port $port might be misconfigured!" | tee -a "$OUTFILE"
        fi
    done

    # Nmap vulnerability scan
    echo "[*] Running Nmap vuln scripts on $ip..." | tee -a "$OUTFILE"
    nmap -sV --script=vuln -p$(echo $open_ports | tr ' ' ',') "$ip" | tee -a "$OUTFILE"

    # Nuclei CVE scans
    if command -v nuclei >/dev/null 2>&1; then
        echo "[*] Running Nuclei CVE templates on $ip..." | tee -a "$OUTFILE"
        nuclei -u "$ip" -t cves/ | tee -a "$OUTFILE"
    else
        echo "Nuclei not installed, skipping." | tee -a "$OUTFILE"
    fi

    echo "[+] Results saved to $OUTFILE"
}

export -f scan_ip
export OUTPUT_DIR MISCONFIG_PORTS

# Run scans in parallel
cat "$INPUT_FILE" | xargs -n 1 -P $THREADS bash -c 'scan_ip "$@"' _

echo -e "\nAll scans completed. Reports are in $OUTPUT_DIR/"
