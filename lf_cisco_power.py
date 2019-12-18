#!/usr/bin/python3
'''
LANforge 192.168.100.178
Controller at 192.168.100.112 admin/Cisco123
Controller is 192.1.0.10
AP is 192.1.0.2

make sure pexpect is installed:
$ sudo yum install python3-pexpect

You might need to install pexpect-serial using pip:
$ pip3 install pexpect-serial

# Example run to cycle through all 8 power settings
# See cisco_power_results.txt when complete.

./lf_cisco_power.py -d 192.168.100.112 -u admin -p Cisco123 -s ssh --port 22 -a VC --lfmgr 192.168.100.178 \
  --station sta00000 --bandwidth "20" --channel "36" --nss 4 --txpower "1 2 3 4 5 6 7 8" --pathloss 54

'''


import sys
if sys.version_info[0] != 3:
    print("This script requires Python 3")
    exit()

import re
import logging
import time
from time import sleep
import pprint
import argparse
import subprocess

NL = "\n"
CR = "\r\n"
Q = '"'
A = "'"
FORMAT = '%(asctime)s %(name)s %(levelname)s: %(message)s'

lfmgr = "127.0.0.1"
lfstation = "sta00000"
lfresource = "1"
outfile = "cisco_power_results.txt"

def usage():
   print("$0 used connect to controller:")
   print("-a|--ap:  AP to act upon")
   print("-d|--dest:  destination host")
   print("-o|--port:  destination port")
   print("-u|--user:  login name")
   print("-p|--pass:  password")
   print("-s|--scheme (serial|telnet|ssh): connect via serial, ssh or telnet")
   print("-l|--log file: log messages here")
   print("-b|--bandwidth: List of bandwidths to test: 20 40 80 160")
   print("-c|--channel: List of channels to test: 36 100")
   print("-n|--nss: List of spatial streams to test: 1 2 3 4")
   print("--outfile: Write results here.")
   print("--station: LANforge station name")
   print("--lfmgr: LANforge manager IP address")
   print("--lfresourcer: LANforge resource ID")
   print("--pathloss:  Calculated path-loss between LANforge station and AP")
   print("--band:  Select band (a | b), a means 5Ghz, b means 2.4")
   print("-h|--help")

# see https://stackoverflow.com/a/13306095/11014343
class FileAdapter(object):
    def __init__(self, logger):
        self.logger = logger
    def write(self, data):
        # NOTE: data can be a partial line, multiple lines
        data = data.strip() # ignore leading/trailing whitespace
        if data: # non-blank
           self.logger.info(data)
    def flush(self):
        pass  # leave it to logging to flush properly

def main():
   global lfmgr
   global lfstation
   global lfresource
   global outfile
    
   parser = argparse.ArgumentParser(description="Cisco TX Power report Script")
   parser.add_argument("-d", "--dest",    type=str, help="address of the cisco controller")
   parser.add_argument("-o", "--port",    type=int, help="control port on the controller")
   parser.add_argument("-u", "--user",    type=str, help="credential login/username")
   parser.add_argument("-p", "--passwd",  type=str, help="credential password")
   parser.add_argument("-s", "--scheme",  type=str, choices=["serial", "ssh", "telnet"], help="Connect via serial, ssh or telnet")
   parser.add_argument("-t", "--tty",     type=str, help="tty serial device")
   parser.add_argument("-l", "--log",     type=str, help="logfile for messages, stdout means output to console")
   #parser.add_argument("-r", "--radio",   type=str, help="select radio")
   parser.add_argument("-a", "--ap",      type=str, help="select AP")
   parser.add_argument("-b", "--bandwidth",        type=str, help="List of bandwidths to test. NA means no change")
   parser.add_argument("-c", "--channel",        type=str, help="List of channels to test. NA means no change")
   parser.add_argument("-n", "--nss",        type=str, help="List of spatial streams to test.  NA means no change")
   parser.add_argument("-T", "--txpower",        type=str, help="List of txpowers to test.  NA means no change")

   parser.add_argument("--station",        type=str, help="LANforge station to use")
   parser.add_argument("--lfmgr",        type=str, help="LANforge Manager IP address")
   parser.add_argument("--lfresource",        type=str, help="LANforge resource ID for the station")
   parser.add_argument("--outfile",     type=str, help="Output file for csv data")
   parser.add_argument("--pathloss",     type=str, help="Calculated pathloss between LANforge Station and AP")
   parser.add_argument("--band",    type=str, help="Select band (a | b), a means 5Ghz, b means 2.4Ghz.  Default is a",
                       choices=["a", "b"])
   
   args = None
   try:
      args = parser.parse_args()
      host = args.dest
      scheme = args.scheme
      user = args.user
      passwd = args.passwd
      logfile = args.log
      if (args.station != None):
          lfstation = args.station
      if (args.lfmgr != None):
          lfmgr = args.lfmgr
      if (args.lfresource != None):
          lfresource = args.lfresource
      if (args.outfile != None):
          outfile = args.outfile
      if (args.band != None):
          band = args.band
      else:
          band = "a"
      filehandler = None
   except Exception as e:
      logging.exception(e);
      usage()
      exit(2);

   console_handler = logging.StreamHandler()
   formatter = logging.Formatter(FORMAT)
   logg = logging.getLogger(__name__)
   logg.setLevel(logging.DEBUG)
   file_handler = None
   if (logfile is not None):
       if (logfile != "stdout"):
           file_handler = logging.FileHandler(logfile, "w")
           file_handler.setLevel(logging.DEBUG)
           file_handler.setFormatter(formatter)
           logg.addHandler(file_handler)
           logging.basicConfig(format=FORMAT, handlers=[file_handler])
       else:
           # stdout logging
           logging.basicConfig(format=FORMAT, handlers=[console_handler])

   if (args.bandwidth == None):
       print("ERROR:  Must specify bandwidths")
       exit(1)

   if (args.channel == None):
       print("ERROR:  Must specify channels")
       exit(1)

   if (args.nss == None):
       print("ERROR:  Must specify NSS")
       exit(1)

   if (args.txpower == None):
       print("ERROR:  Must specify txpower")
       exit(1)

   if (args.pathloss == None):
       print("ERROR:  Pathloss must be specified.")
       exit(1)

   csv = open(outfile, "w")
   csv.write("Cfg-Pathloss\tCfg-Channel\tCfg-NSS\tCfg-BW\tCfg-Power\tCombined-Signal\tAnt-0\tAnt-1\tAnt-2\tAnt-3\tAP-BSSID\tRpt-BW\tRpt-Channel\tRpt-Mode\tRpt-NSS\tRpt-Noise\tRpt-Rxrate\tCtrl-AP-MAC\tCtrl-Channel\tCtrl-Power\tCtrl-dBm\tCalc-dBm-Combined\tDiff-dBm-Combined\tCalc-Ant-1\tCalc-Ant-2\tCalc-Ant-3\tCalc-Ant-4\tDiff-Ant-1\tDiff-Ant-2\tDiff-Ant-3\tDiff-Ant-4\tWarnings-and-Errors")
   csv.write("\n");
   csv.flush()

   bandwidths = args.bandwidth.split()
   channels = args.channel.split()
   nss = args.nss.split()
   txpowers = args.txpower.split()

   # Find LANforge station parent radio
   parent = None
   port_stats = subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", lfstation,
                                "--show_port", "Parent/Peer"], capture_output=True);
   pss = port_stats.stdout.decode('utf-8', 'ignore');
   for line in pss.splitlines():
       m = re.search('Parent/Peer:\s+(.*)', line)
       if (m != None):
           parent = m.group(1)

   for ch in channels:
       for n in nss:
           for bw in bandwidths:
               if (n != "NA"):
                   if (parent == None):
                       print("ERROR:  Skipping setting the spatial streams because cannot find Parent radio for station.")
                   else:
                       # Set nss on LANforge Station, not sure it can be done on AP
                       ni = int(n);
                       if (bw == "160"):
                           # 9984 hardware needs 2 chains to do one NSS at 160Mhz
                           if (ni > 2):
                               print("NOTE: Skipping NSS %s for 160Mhz, LANforge radios do not support more than 2NSS at 160Mhz currently."%(n))
                               continue
                           else:
                               # Set radio to 2x requested value for 160Mhz
                               ni *= 2
                   antset = 0 # all available
                   if (ni == 1):
                       antset = 1
                   if (ni == 2):
                       antset = 4
                   if (ni == 3):
                       antset = 7
                   set_cmd = "set_wifi_radio 1 %s %s NA NA NA NA NA NA NA NA NA %s"%(lfresource, parent, antset)
                   print("Setting LANforge radio to %s NSS with command: %s"%(ni, set_cmd))
                   subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", parent,
                                   "--cli_cmd", set_cmd], capture_output=True)
               
               for tx in txpowers:

                   # TODO:  Down station
                   port_stats = subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", lfstation,
                                                "--set_ifstate", "down"]);
                   
                   # Disable AP, apply settings, enable AP
                   subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                   "--action", "disable"])
                   subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                   "--action", "cmd", "--value", "config 802.11a disable network"])
                   subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                   "--action", "cmd", "--value", "config 802.11b disable network"])

                   if (tx != "NA"):
                       subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                       "--action", "txPower", "--value", tx])
                   if (bw != "NA"):
                       subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                       "--action", "bandwidth", "--value", bw])

                   # NSS is set on the station earlier...
                       
                   if (ch != "NA"):
                       subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                       "--action", "channel", "--value", ch])
                   
                   subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                   "--action", "cmd", "--value", "config 802.11a enable network"])
                   subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                   "--action", "cmd", "--value", "config 802.11b enable network"])
                   subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                   "--action", "enable"])

                   # Wait a bit for AP to come back up
                   time.sleep(1);
                   advanced = subprocess.run(["./cisco_wifi_ctl.py", "-d", args.dest, "-u", args.user, "-p", args.passwd, "-a", args.ap, "--band", band, "-s", "ssh",
                                              "--action", "advanced"], capture_output=True)
                   pss = advanced.stdout.decode('utf-8', 'ignore');
                   print(pss)

                   searchap = False
                   cc_mac = ""
                   cc_ch = ""
                   cc_power = ""
                   cc_dbm = ""
                   for line in pss.splitlines():
                       if (line.startswith("---------")):
                           searchap = True
                           continue

                       if (searchap):
                           pat = "%s\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+\(\s*(\S+)\s+dBm"%(args.ap)
                           m = re.search(pat, line)
                           if (m != None):
                               cc_mac = m.group(1)
                               cc_ch = m.group(2);
                               cc_power = m.group(3)
                               cc_power = cc_power.replace("/", " of ", 1) # spread-sheets turn 1/8 into a date
                               cc_dbm = m.group(4)
                               break

                   # Up station
                   subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", lfstation,
                                   "--set_ifstate", "up"]);

                   i = 0
                   wait_ip_print = False;
                   wait_assoc_print = False;
                   # Wait untill LANforge station connects
                   while True:
                       port_stats = subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", lfstation,
                                                    "--show_port", "AP,IP,Mode,NSS,Bandwidth,Channel,Signal,Noise,Status,RX-Rate"], capture_output=True);
                       pss = port_stats.stdout.decode('utf-8', 'ignore');

                       _status = None
                       _ip = None

                       for line in pss.splitlines():
                           m = re.search('Status:\s+(.*)', line)
                           if (m != None):
                               _status = m.group(1)
                           m = re.search('IP:\s+(.*)', line)
                           if (m != None):
                               _ip = m.group(1)

                       #print("IP %s  Status %s"%(_ip, _status))
                       
                       if (_status == "Authorized"):
                           if ((_ip != None) and (_ip != "0.0.0.0")):
                               print("Station is associated with IP address.")
                               break
                           else:
                               if (not wait_ip_print):
                                   print("Waiting for station to get IP Address.")
                                   wait_ip_print = True
                       else:
                           if (not wait_assoc_print):
                               print("Waiting for station to associate.")
                               wait_assoc_print = True

                       i += 1
                       if (i > 60):
                           print("ERROR:  Station did not connect within 60 seconds.")
                           break

                       time.sleep(1)

                   # Wait 10 more seconds
                   print("Waiting 10 seconds to let traffic run for a bit, Channel %s NSS %s BW %s TX-Power %s"%(ch, n, bw, tx))
                   time.sleep(10)

                   # Gather probe results and record data, verify NSS, BW, Channel
                   i = 0;
                   sig = None
                   ants = []
                   while True:                       
                       time.sleep(1)
                       port_stats = subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", lfstation,
                                                    "--cli_cmd", "probe_port 1 %s %s"%(lfresource, lfstation)], capture_output=True);
                       pss = port_stats.stdout.decode('utf-8', 'ignore');

                       foundit = False
                       for line in pss.splitlines():
                           #print("probe-line: %s"%(line))
                           m = re.search('signal avg:\s+(\S+)\s+\[(.*)\]\s+dBm', line)
                           if (m != None):
                               sig = m.group(1)
                               ants = m.group(2).split();
                               q = 0
                               for a in ants:
                                   ants[q] = ants[q].replace(",", "", 1)
                                   q += 1

                               #print("sig: %s  ants: %s ants-len: %s n: %s"%(sig, m.group(2), len(ants), n))

                               if (len(ants) == int(n)):
                                   foundit = True
                                   break
                               else:
                                   print("Looking for %s spatial streams, signal avg reported fewer: %s"%(n, m.group(1)))

                       if (foundit):
                           break

                       i += 1
                       if (i > 10):
                           print("Tried and failed 10 times to find correct spatial streams, continuing.")
                           while (len(ants) < int(n)):
                               ants.append("")
                               break
                           break

                   antstr = ""
                   for x in range(4):
                       if (x < int(n)):
                           antstr += ants[x]
                       else:
                           antstr += " "
                       antstr += "\t"

                   port_stats = subprocess.run(["./lf_portmod.pl", "--manager", lfmgr, "--card",  lfresource, "--port_name", lfstation,
                                                    "--show_port", "AP,IP,Mode,NSS,Bandwidth,Channel,Signal,Noise,Status,RX-Rate"], capture_output=True);
                   pss = port_stats.stdout.decode('utf-8', 'ignore');

                   _ap = None
                   _bw = None
                   _ch = None
                   _mode = None
                   _nss = None
                   _noise = None
                   _rxrate = None

                   for line in pss.splitlines():
                       m = re.search('AP:\s+(.*)', line)
                       if (m != None):
                           _ap = m.group(1)
                       m = re.search('Bandwidth:\s+(.*)Mhz', line)
                       if (m != None):
                           _bw = m.group(1)
                       m = re.search('Channel:\s+(.*)', line)
                       if (m != None):
                           _ch = m.group(1)
                       m = re.search('Mode:\s+(.*)', line)
                       if (m != None):
                           _mode = m.group(1)
                       m = re.search('NSS:\s+(.*)', line)
                       if (m != None):
                           _nss = m.group(1)
                       m = re.search('Noise:\s+(.*)', line)
                       if (m != None):
                           _noise = m.group(1)
                       m = re.search('RX-Rate:\s+(.*)', line)
                       if (m != None):
                           _rxrate = m.group(1)

                   pi = int(args.pathloss)
                   calc_dbm = int(sig) + pi
                   calc_ant1 = int(ants[0]) + pi
                   calc_ant2 = 0
                   calc_ant3 = 0
                   calc_ant4 = 0
                   if (len(ants) > 1):
                       calc_ant2 = int(ants[1]) + pi
                   if (len(ants) > 2):
                       calc_ant3 = int(ants[2]) + pi
                   if (len(ants) > 3):
                       calc_ant4 = int(ants[3]) + pi

                   diff_a1 = ""
                   diff_a2 = ""
                   diff_a3 = ""
                   diff_a4 = ""

                   cc_dbmi = int(cc_dbm)
                   diff_dbm = calc_dbm - cc_dbmi
                   if (int(_nss) == 1):
                       diff_a1 = calc_ant1 - cc_dbmi
                   if (int(_nss) == 2):
                       diff_a1 = calc_ant1 - (cc_dbmi - 3)
                       diff_a2 = calc_ant2 - (cc_dbmi - 3)
                   if (int(_nss) == 3):
                       diff_a1 = calc_ant1 - (cc_dbmi - 5)
                       diff_a2 = calc_ant2 - (cc_dbmi - 5)
                       diff_a3 = calc_ant3 - (cc_dbmi - 5)
                   if (int(_nss) == 4):
                       diff_a1 = calc_ant1 - (cc_dbmi - 6)
                       diff_a2 = calc_ant2 - (cc_dbmi - 6)
                       diff_a3 = calc_ant3 - (cc_dbmi - 6)
                       diff_a4 = calc_ant4 - (cc_dbmi - 6)
                       
                   ln = "%s\t%s\t%s\t%s\t%s\t%s\t%s%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s"%(
                       args.pathloss, ch, n, bw, tx, sig,
                       antstr, _ap, _bw, _ch, _mode, _nss, _noise, _rxrate,
                       cc_mac, cc_ch, cc_power, cc_dbm,
                       calc_dbm, diff_dbm, calc_ant1, calc_ant2, calc_ant3, calc_ant4,
                       diff_a1, diff_a2, diff_a3, diff_a4
                     )

                   #print("RESULT: %s"%(ln))
                   csv.write(ln)
                   csv.write("\t");
                   if (_bw != bw):
                       err = "ERROR:  Requested bandwidth: %s != station's reported bandwidth: %s.  "%(bw, _bw)
                       print(err)
                       csv.write(err)
                   if (_nss != n):
                       err = "ERROR:  Station NSS: %s != configured: %s.  "%(_nss, n)
                       print(err)
                       csv.write(err)
                   
                   csv.write("\n");
                   csv.flush()

# ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
if __name__ == '__main__':
    main()
    print("Results stored in %s"%(outfile))

####
####
####