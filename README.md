# macOS-Diagnosis-Script
This bash script runs on any Mac (no extra tools needed) and prints a color-coded report to the terminal while also saving a full copy to ~/Desktop/Mac_Diagnostics/. It covers:


System -macOS version/build, hostname, uptime, boot volume

Hardware - model, chip/CPU, serial number, RAM, core count

Battery - cycle count, condition, max capacity (skipped on desktops)

Storage -disk usage %, SMART health status, low-space warning

Memory pressure

Network -active interface, local/public IP, MAC address, gateway, DNS, Wi-Fi network name, internet reachability test

MDM/enrollment status (via profiles status)

Software updates pending

Recent crash reports & kernel panics (last 7 days)

Top CPU/memory-consuming processes

Login items & LaunchAgents

Application versions — checks a default set (Safari, Chrome, Firefox, Slack, Zoom, Word, VS Code, Docker) or a custom list you supply

Time Machine — destination info, latest backup timestamp, and an age-based warning if backups are overdue

Firewall & Gatekeeper — application firewall on/off state, Gatekeeper assessment status


Export formats via a new --format flag:

text (default) — same readable .txt report as before
json — structured .json file
csv — .csv with Field,Value rows
all — writes all three


To use it:

./mac_diagnostics.sh # plain text (default)

./mac_diagnostics.sh --format json # JSON export

./mac_diagnostics.sh --format csv # CSV export

./mac_diagnostics.sh --format all # txt + json + csv

./mac_diagnostics.sh --apps "Notion,Docker,Figma" # check specific app versions

sudo ./mac_diagnostics.sh --format all --apps "Slack,Postman"


Each section is clearly labeled with [OK], [WARN], or [ISSUE] tags so you can scan quickly for problems.
