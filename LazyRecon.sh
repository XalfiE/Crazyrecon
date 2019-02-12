#!/bin/bash

TARGET=$1

WORKING_DIR=$(pwd)
TOOLS_PATH="$WORKING_DIR/tools"
WORDLIST_PATH="$WORKING_DIR/wordlists"
RESULTS_PATH="$WORKING_DIR/results/$TARGET"
SUB_PATH="$RESULTS_PATH/subdomain"
IP_PATH="$RESULTS_PATH/ip"
PSCAN_PATH="$RESULTS_PATH/portscan"
SSHOT_PATH="$RESULTS_PATH/screenshot"
DIR_PATH="$RESULTS_PATH/directory"

RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

displayLogo(){
echo -e "
██╗      █████╗ ███████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
██║     ██╔══██╗╚══███╔╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
██║     ███████║  ███╔╝  ╚████╔╝ ██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
██║     ██╔══██║ ███╔╝    ╚██╔╝  ██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
███████╗██║  ██║███████╗   ██║   ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══  
${RED}v1.0${RESET} by ${YELLOW}@CaptMeelo${RESET}
"
}


checkArgs(){
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}[+] Usage:${RESET} $0 <domain>\n"
        exit 1
    fi
}


runBanner(){
    name=$1
    echo -e "${RED}\n[+] Running $name...${RESET}"
}


setupDir(){
    echo -e "${GREEN}--==[ Setting things up ]==--${RESET}"
    echo -e "${RED}\n[+] Creating results directories...${RESET}"
    rm -rf $RESULTS_PATH
    mkdir -p $SUB_PATH $IP_PATH $PSCAN_PATH $SSHOT_PATH $DIR_PATH
    echo -e "${BLUE}[*] $SUB_PATH${RESET}"
    echo -e "${BLUE}[*] $IP_PATH${RESET}"
    echo -e "${BLUE}[*] $PSCAN_PATH${RESET}"
    echo -e "${BLUE}[*] $SSHOT_PATH${RESET}"
    echo -e "${BLUE}[*] $DIR_PATH${RESET}"
}


enumSubs(){
    echo -e "${GREEN}\n--==[ Enumerating subdomains ]==--${RESET}"
    runBanner "amass"
    ~/go/bin/amass -d $TARGET -o $SUB_PATH/amass.txt

    runBanner "subfinder"
    ~/go/bin/subfinder -d $TARGET -t 50 -nW --silent -o $SUB_PATH/subfinder.txt

    runBanner "massdns"
    $TOOLS_PATH/massdns/scripts/subbrute.py $WORDLIST_PATH/dns_all.txt $TARGET | $TOOLS_PATH/massdns/bin/massdns -r $TOOLS_PATH/massdns/lists/resolvers.txt -q -t A -o S -w $SUB_PATH/massdns.raw

    echo -e "${RED}\n[+] Combining subdomains...${RESET}"
    cat $SUB_PATH/massdns.raw | cut -d " " -f1 | rev | cut -d "." -f 2- | rev > $SUB_PATH/massdns.txt
    cat $SUB_PATH/*.txt | sort | awk '{print tolower($0)}' | uniq > $SUB_PATH/final-subdomains.txt
    echo -e "${BLUE}[*] Check the list of subdomains at $SUB_PATH/final-subdomains.txt${RESET}"

    echo -e "${GREEN}\n--==[ Checking for subdomain takeovers ]==--${RESET}"
    runBanner "subjack"
    ~/go/bin/subjack -a -ssl -t 20 -v -c ~/go/src/github.com/haccer/subjack/fingerprints.json -w $SUB_PATH/final-subdomains.txt -o $SUB_PATH/final-takeover.tmp
    cat $SUB_PATH/final-takeover.tmp | grep -v "Not Vulnerable" > $SUB_PATH/final-takeover.txt
    rm $SUB_PATH/final-takeover.tmp
    echo -e "${BLUE}[*] Check subjack's result at $SUB_PATH/final-takeover.txt${RESET}"
}


enumIPs(){
    echo -e "${GREEN}\n--==[ Resolving & enumerating IP addresses ]==--${RESET}"
    runBanner "massdns"
    $TOOLS_PATH/massdns/bin/massdns -r $TOOLS_PATH/massdns/lists/resolvers.txt -q -t A -o S -w $IP_PATH/massdns.raw $SUB_PATH/final-subdomains.txt

    runBanner "IPOsint"
    $TOOLS_PATH/IPOsint/ip-osint.py -t $TARGET -o $IP_PATH/iposint.txt

    echo -e "${RED}\n[+] Combining IP addresses...${RESET}"
    cat $IP_PATH/massdns.raw | grep -e ' A ' |  cut -d 'A' -f 2 | tr -d ' ' > $IP_PATH/massdns.txt
    cat $IP_PATH/*.txt | sort -V | uniq > $IP_PATH/final-ips.txt
    echo -e "${BLUE}[*] Check the list of IP addresses at $IP_PATH/final-ips.txt${RESET}"
}


portScan(){
    echo -e "${GREEN}\n--==[ Port-scanning IP addresses ]==--${RESET}"
    # Based on exp, the sweet spot for the rate is 10k. More than 10k causes masscan to miss some open ports
    runBanner "masscan"
    sudo $TOOLS_PATH/masscan/bin/masscan -p1-65535 --rate 10000 --wait 0 --open -iL $IP_PATH/final-ips.txt -oX $PSCAN_PATH/masscan.xml
    xsltproc -o $PSCAN_PATH/final-masscan.html $TOOLS_PATH/nmap-bootstrap.xsl $PSCAN_PATH/masscan.xml
    echo -e "${BLUE}[*] Check masscan's HTML report at $PSCAN_PATH/final-masscan.html${RESET}"
}


visualRecon(){
    echo -e "${GREEN}\n--==[ Taking screenshots ]==--${RESET}"
    runBanner "aquatone"
    cat $SUB_PATH/final-subdomains.txt | ~/go/bin/aquatone -http-timeout 10000 -scan-timeout 300 -threads 10 -ports xlarge -out $SSHOT_PATH/aquatone/
    echo -e "${BLUE}[*] Check the result at $SSHOT_PATH/aquatone/aquatone_report.html${RESET}"
}


bruteDir(){
    echo -e "${GREEN}\n--==[ Bruteforcing directories ]==--${RESET}"
    runBanner "gobuster"
    echo -e "${BLUE}[*]Creting output directory...${RESET}"
    mkdir -p $DIR_PATH/gobuster
    for url in $(cat $SSHOT_PATH/aquatone/aquatone_urls.txt); do
        fqdn=$(echo $url | sed -e 's;https\?://;;' | sed -e 's;/.*$;;')
        ~/go/bin/gobuster -t 100 -k -e -f -r -w $WORDLIST_PATH/dir_all.txt -u $url -o $DIR_PATH/gobuster/$fqdn.tmp
        if [ ! -s $DIR_PATH/gobuster/$fqdn.tmp ]; then
            rm $DIR_PATH/gobuster/$fqdn.tmp
        else
            cat $DIR_PATH/gobuster/$fqdn.tmp | sort -k 3 -n > $DIR_PATH/gobuster/$fqdn.txt
            rm $DIR_PATH/gobuster/$fqdn.tmp
        fi
    done
    echo -e "${BLUE}[*] Check the results at $DIR_PATH/gobuster/${RESET}"

    runBanner "dirsearch"
    echo -e "${BLUE}[*]Creting output directory...${RESET}"
    mkdir -p $DIR_PATH/dirsearch
    for url in $(cat $SSHOT_PATH/aquatone/aquatone_urls.txt); do
        fqdn=$(echo $url | sed -e 's;https\?://;;' | sed -e 's;/.*$;;')
        $TOOLS_PATH/dirsearch/dirsearch.py -b -t 100 -e php,asp,aspx,jsp,html,zip,jar,sql -x 500,503 -r -w $WORDLIST_PATH/raft-large-words.txt -u $url --plain-text-report=$DIR_PATH/dirsearch/$fqdn.tmp
        if [ ! -s $DIR_PATH/dirsearch/$fqdn.tmp ]; then
            rm $DIR_PATH/dirsearch/$fqdn.tmp
        else
            cat $DIR_PATH/dirsearch/$fqdn.tmp | sort -k 1 -n > $DIR_PATH/dirsearch/$fqdn.txt
            rm $DIR_PATH/dirsearch/$fqdn.tmp
        fi
    done
    echo -e "${BLUE}[*] Check the results at $DIR_PATH/dirsearch/${RESET}"
}


# Main function
displayLogo
checkArgs $TARGET
setupDir
enumSubs
enumIPs
portScan
visualRecon
bruteDir

echo -e "${GREEN}\n--==[ DONE ]==--${RESET}"