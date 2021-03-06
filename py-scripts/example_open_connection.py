#!/usr/bin/env python3

import sys
import os
if sys.version_info[0] != 3:
    print("This script requires Python 3")
    exit(1)

if 'py-json' not in sys.path:
    sys.path.append(os.path.join(os.path.abspath('..'), 'py-json'))
import LANforge
from LANforge.lfcli_base import LFCliBase
from LANforge import LFUtils
import realm
import argparse
import time
import pprint


class IPv4Test(LFCliBase):
    def __init__(self, host, port, ssid, security, password, sta_list=None, number_template="00000", _debug_on=False,
                 _exit_on_error=False,
                 _exit_on_fail=False):
        super().__init__(host, port, _debug=_debug_on, _halt_on_error=_exit_on_error, _exit_on_fail=_exit_on_fail)
        self.host = host
        self.port = port
        self.ssid = ssid
        self.security = security
        self.password = password
        self.sta_list = sta_list
        self.timeout = 120
        self.number_template = number_template
        self.debug = _debug_on
        self.local_realm = realm.Realm(lfclient_host=self.host, lfclient_port=self.port)
        self.station_profile = self.local_realm.new_station_profile()

        self.station_profile.lfclient_url = self.lfclient_url
        self.station_profile.ssid = self.ssid
        self.station_profile.ssid_pass = self.password,
        self.station_profile.security = self.security
        self.station_profile.number_template_ = self.number_template
        self.station_profile.mode = 0

    def build(self):
        # Build stations
        self.station_profile.use_security(self.security, self.ssid, self.password)
        self.station_profile.set_number_template(self.number_template)
        print("Creating stations")
        self.station_profile.set_command_flag("add_sta", "create_admin_down", 1)
        self.station_profile.set_command_param("set_port", "report_timer", 1500)
        self.station_profile.set_command_flag("set_port", "rpt_timer", 1)
        self.station_profile.create(radio="wiphy0", sta_names_=self.sta_list, debug=self.debug)
        self._pass("PASS: Station build finished")
        self.station_profile.admin_up()

    def cleanup(self, sta_list):
        self.station_profile.cleanup(sta_list)
        LFUtils.wait_until_ports_disappear(base_url=self.lfclient_url, port_list=sta_list,
                                           debug=self.debug)

def main():
    lfjson_host = "localhost"
    lfjson_port = 8080

    parser = LFCliBase.create_basic_argparse(
        prog='example_open_connection.py',
        # formatter_class=argparse.RawDescriptionHelpFormatter,
        formatter_class=argparse.RawTextHelpFormatter,
        epilog='''\
                Example code that creates a specified amount of stations on a specified SSID using Open security.
                ''',

        description='''\
        example_wpa_connection.py
        --------------------

        Generic command example:
    python3 ./example_open_connection.py  \\
        --host localhost (optional) \\
        --port 8080  (optional) \\
        --num_stations 3 \\
        --security {open|wep|wpa|wpa2|wpa3} \\
        --ssid netgear-open \\
        --debug 

    Note:   multiple --radio switches may be entered up to the number of radios available:
                     --radio wiphy0 <stations> <ssid> <ssid password>  --radio <radio 01> <number of last station> <ssid> <ssid password>
            ''')

    args = parser.parse_args()
    num_sta = 2
    if (args.num_stations is not None) and (int(args.num_stations) > 0):
        num_sta = int(args.num_stations)

    station_list = LFUtils.portNameSeries(prefix_="sta",
                                        start_id_=0,
                                        end_id_=num_sta-1,
                                        padding_number_=10000)
    ip_test = IPv4Test(lfjson_host, lfjson_port, ssid=args.ssid, password=args.passwd,
                       security=args.security, sta_list=station_list)
    ip_test.cleanup(station_list)
    ip_test.timeout = 60
    ip_test.build()

if __name__ == "__main__":
    main()
