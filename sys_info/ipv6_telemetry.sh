#!/bin/bash
echo ##active_line2##

echo ##active_line3##
# Whois
echo ##active_line4##
echo 'WHOIS'
echo ##active_line5##
whois ##ANONYMIZED##
echo ##active_line6##

echo ##active_line7##
# Nslookup
echo ##active_line8##
echo 'NSLOOKUP'
echo ##active_line9##
nslookup ##ANONYMIZED##
echo ##active_line10##

echo ##active_line11##
# MTR
echo ##active_line12##
echo 'MTR'
echo ##active_line13##
mtr --report --report-wide --report-cycles 10 ##ANONYMIZED##
echo ##active_line14##

echo ##active_line15##
# IPCALC
echo ##active_line16##
echo 'IPCALC'
echo ##active_line17##
ipcalc ##ANONYMIZED##
echo ##active_line18##

echo ##active_line19##
# SS
echo ##active_line20##
echo 'SS'
echo ##active_line21##
ss -a -A inet6
echo ##active_line22##

echo ##active_line23##
# NETSTAT
echo ##active_line24##
echo 'NETSTAT'
echo ##active_line25##
netstat -6av
echo ##active_line26##

echo ##active_line27##
# TELNET NOTE
echo ##active_line28##
echo 'TELNET'
echo ##active_line29##
echo 'Telnet command is interactive and cannot be logged into a file'
echo ##active_line30##
