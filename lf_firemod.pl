#!/usr/bin/perl -w

# This program is used to create, show, and modify existing connections
# and get some basic information from LANforge.

# Written by Candela Technologies Inc.
#  Udated by:
#
#

use strict;
use warnings;
use diagnostics;
use Carp;
$SIG{ __DIE__  } = sub { Carp::confess( @_ ) };
$SIG{ __WARN__ } = sub { Carp::confess( @_ ) };

# Un-buffer output
$| = 1;
use lib '/home/lanforge/scripts';
use LANforge::Endpoint;
use LANforge::Port;
use LANforge::Utils;
use Net::Telnet ();
use Getopt::Long;

use constant      NA          => "NA";
use constant      NL          => "\n";
use constant      shelf_num   => 1;

# Default values for ye ole cmd-line args.
our $resource         = 1;
our $quiet            = "yes";
our $endp_name        = "";
our $endp_cmd         = "";
our $port_name        = "";
our $speed            = "-1";
our $action           = "show_port";
our $do_cmd           = "NA";
our $lfmgr_host       = "localhost";
our $lfmgr_port       = 4001;
our $endp_vals        = undef;
our $ip_port          = "-1"; # let lf choose
our $multicon         = "0"; #no multicon

# For creating multicast endpoints
our $endp_type        = undef; #"mc_udp"; this needs to be explicit
our $mcast_addr       = "224.9.9.9";
our $mcast_port       = "9999";
our $max_speed        = "-1";
our $rcv_mcast        = "YES";
our $min_pkt_sz       = "-1";
our $max_pkt_sz       = "-1";
our $use_csums        = "NO";  # Use LANforge checksums in payload?
our $ttl              = 32;
our $report_timer     = 5000;
our $tos              = "";
our $arm_pps          = "";
our $arm_cpu_id       = "NA";
# For cross connects
our $cx_name         = "";
our $cx_endps        = "";
our $list_cx_name    = "all";
our $test_mgr        = "default_tm";
our $list_test_mgr   = "all";

our $fail_msg         = "";
our $manual_check     = 0;

our @known_endp_types = split(',', "lf_udp,lf_udp6,lf_tcp,lf_tcp6,mc_udp,mc_udp6,generic");
our @known_tos       = split(',', "DONT-SET,LOWDELAY,THROUGHPUT,RELIABILITY,LOWCOST");

########################################################################
# Nothing to configure below here, most likely.
########################################################################

our $usage = "$0  --action { list_ports | show_port
                            | list_endp | create_endp | create_arm | show_endp | set_endp
                            | do_cmd | start_endp | stop_endp | delete_endp
                            | create_cx | list_cx | show_cx | delete_cx } ]
  [--endp_vals {key,key,key,key}]
      # show_endp output can be narrowed with key-value arguments
      # Examples:
      #  --action show_endp --endp_vals MinTxRate,DestMAC,Avg-Jitter
      # Not available: Latency,Pkt-Gaps, or rows below steps-failed.
      # Special Keys:
      #  --endp_vals tx_bps         (Tx Bytes)
      #  --endp_vals rx_bps         (Rx Bytes)
  [--mgr       {host-name | IP}]
  [--mgr_port  {ip port}]
  [--cmd       {lf-cli-command text}]
  [--endp_name {name}]
  [--endp_cmd  {generic-endp-command}]
  [--port_name {name}]
  [--resource  {number}]
  [--speed     {speed in bps}]
  [--tos       { ".join(' | ', @::known_tos)." },{priority}]
  [--max_speed {speed in bps}]
  [--quiet     { yes | no }]
  [--endp_type { ".join(' | ', @::known_endp_types)." }]
  [--mcast_addr {multicast address, for example: 224.4.5.6}]
  [--mcast_port {multicast port number}]
  [--min_pkt_sz {minimum payload size in bytes}]
  [--max_pkt_sz {maximum payload size in bytes}]
  [--rcv_mcast { yes (receiver) | no (transmitter) }]
  [--use_csums { yes | no, should we checksum the payload }]
  [--ttl       {time-to-live}]
  [--report_timer {miliseconds}]
  [--cx_name   {connection name}]
  [--cx_endps  {endp1},{endp2}]
  [--test_mgr  {default_tm|all|other-tm-name}]
  [--arm_pps   {packets per second}]
  [--ip_port   {-1 (let LF choose, AUTO) | 0 (let OS choose, ANY) | specific IP port}]
  [--multicon  {0 (no multi-conn, Normal) | number of connections (TCP only)}]
  [--log_cli   {1|filename}]
Example:
 $0 --action set_endp --endp_name udp1-A --speed 154000

 $0 --action create_endp --endp_name mcast_xmit_1 --speed 154000 \\
   --endp_type mc_udp   --mcast_addr 224.9.9.8 --mcast_port 9998 \\
   --rcv_mcast NO       --port_name eth1 \\
   --min_pkt_sz 1072    --max_pkt_sz 1472 \\
   --use_csums NO       --ttl 32 \\
   --quiet no --report_timer 1000

 $0 --action create_endp --endp_name bc1 --speed 256000 \\
   --endp_type lf_tcp   --tos THROUGHPUT,100 --port_name rd0#1

 $0 --action create_endp --endp_name ping1 --port_name sta0 --endp_cmd \"lfping -p deadbeef000 -I sta0 8.8.4.4\"
   --endp_type generic

 $0 --action list_cx --test_mgr all --cx_name all

 $0 --action create_cx --cx_name L301 \\
   --cx_endps ep_rd0a,ep_rd1a --report_timer 1000

 $0 --action create_arm --endp_name arm01-A --port_name eth1 \\
   --arm_pps 80000 --min_pkt_sz 1472 --max_pkt_sz 1514 --tos LOWDELAY,100

 $0 --mgr jedtest --action create_cx --cx_name arm-01 --cx_endps arm01-A,arm01-B

 $0 --mgr localhost --action create_endp --endp_name test1a --speed 10000000 \\
   --endp_type lf_tcp --port_name eth5 --ip_port 0 --multicon 10

 $0 --mgr localhost --resource 3 --action create_endp --endp_name test1b --speed 0 \\
   --endp_type lf_tcp --port_name wlan2 --multicon 1

 $0 --mgr localhost --action create_cx --cx_name test1 --cx_endps test1a,test1b
";

my $i = 0;
my $cmd;
die($::usage) if (@ARGV < 2);
my $log_cli = "unset"; # use ENV{LOG_CLI} elsewhere

GetOptions
(
        'endp_name|e=s' => \$::endp_name,
        'endp_cmd=s'    => \$::endp_cmd,
        'endp_vals|o=s' => \$::endp_vals,
        'action|a=s'    => \$::action,
        'cmd|c=s'       => \$::do_cmd,
        'mgr|m=s'       => \$::lfmgr_host,
        'mgr_port|p=i'  => \$::lfmgr_port,
        'resource|r=i'  => \$::resource,
        'port_name=s'   => \$::port_name,
        'speed|s=i'     => \$::speed,
        'max_speed=s'   => \$::speed,
        'quiet|q=s'     => \$::quiet,
        'endp_type=s'   => \$::endp_type,
        'mcast_addr=s'  => \$::mcast_addr,
        'mcast_port=s'  => \$::mcast_port,
        'min_pkt_sz=s'  => \$::min_pkt_sz,
        'max_pkt_sz=s'  => \$::max_pkt_sz,
        'rcv_mcast=s'   => \$::rcv_mcast,
        'use_csums=s'   => \$::use_csums,
        'ttl=i'         => \$::ttl,
        'report_timer=i' => \$::report_timer,
        'cx_name=s'     => \$::cx_name,
        'cx_endps=s'    => \$::cx_endps,
        'test_mgr=s'    => \$::test_mgr,
        'tos=s'         => \$::tos,
        'arm_pps=i'     => \$::arm_pps,
        'ip_port=i'     => \$::ip_port,
        'multicon=i'    => \$::multicon,
        'log_cli=s{0,1}'=> \$log_cli,
) || die("$::usage");

if ($::quiet eq "0") {
  $::quiet = "no";
}
elsif ($::quiet eq "1") {
  $::quiet = "yes";
}

if (defined $log_cli) {
  if ($log_cli ne "unset") {
    # here is how we reset the variable if it was used as a flag
    if ($log_cli eq "") {
      $ENV{'LOG_CLI'} = 1;
    }
    else {
      $ENV{'LOG_CLI'} = $log_cli;
    }
  }
}

if ($::do_cmd ne "NA") {
  $::action = "do_cmd";
}
our @valid_actions = split(/,/, "show_endp,set_endp,start_endp,stop_endp,delete_endp,create_endp,create_arm,"
       ."show_port,do_cmd,list_ports,list_endp,create_cx,list_cx,show_cx,delete_cx" );

if (! (grep {$_ eq $::action} @::valid_actions )) {
  die("Invalid action: $::action\n$::usage\n");
}
our @actions_needing_endp = split(/,/, "set_endp,start_endp,stop_endp,delete_endp,create_endp,create_arm");
if (grep {$_ eq $::action} @actions_needing_endp) {
  if (length($::endp_name) == 0) {
    print "ERROR:  Must specify endp_name.\n";
    die("$::usage");
  }
}
if ($::quiet eq "1" ) {
   $::quiet = "yes";
}
# Open connection to the LANforge server.

# Wait up to 60 seconds when requesting info from LANforge.
my $t = new Net::Telnet(Prompt => '/default\@btbits\>\>/',
         Timeout => 60);

$t->open(Host    => $::lfmgr_host,
         Port    => $::lfmgr_port,
         Timeout => 10);

$t->max_buffer_length(16 * 1024 * 1000); # 16 MB buffer
$t->waitfor("/btbits\>\>/");

# Configure our utils.
our $utils = new LANforge::Utils();
$::utils->telnet($t);         # Set our telnet object.
if ($::utils->isQuiet()) {
  if (defined $ENV{'LOG_CLI'} && $ENV{'LOG_CLI'} ne "") {
    $::utils->cli_send_silent(0);
  }
  else {
    $::utils->cli_send_silent(1); # Do not show input to telnet
  }
  $::utils->cli_rcv_silent(1);  # Repress output from telnet
}
else {
  $::utils->cli_send_silent(0); # Show input to telnet
  $::utils->cli_rcv_silent(0);  # Show output from telnet
}
$::utils->log_cli("# $0 ".`date "+%Y-%m-%d %H:%M:%S"`);

if (grep {$_ eq $::action} split(',', "show_endp,set_endp,create_endp,create_arm,list_endp")) {
	$::max_speed = $::speed if( $::max_speed eq "-1");
   if ($::action eq "list_endp") {
      my @lines = split(NL, $::utils->doAsyncCmd("nc_show_endpoints all"));
      for my $line (@lines) {
         if ($line =~ /^([A-Z]\w+)\s+\[(.*?)\]/) {
            print "$line\n";
         }
      }
   }
   elsif ($::action eq "show_endp") {
      if ((defined $::endp_vals) && ("$::endp_vals" ne "")) {

         my %option_map    = ();
         my $option        = '';
         for $option (split(',', $::endp_vals)) {
            #print "OPTION[$option]\n";
            next if( $option =~ /Latency/);
            next if( $option =~ /Pkt-Gaps/);
            #next if( $option =~ /\s/);
            if( $option =~ /rx_pps/    ) { $option = "Rx Pkts"; }
            if( $option =~ /tx_pps/    ) { $option = "Tx Pkts"; }
            if( $option =~ /rx_pkts/   ) { $option = "Rx Pkts"; }
            if( $option =~ /tx_pkts/   ) { $option = "Tx Pkts"; }

            # we don't know if we're armageddon or layer 3
            if( $option =~ /tx_bytes/  ) {
               $option_map{ "Tx Bytes" } = '';
               $option = "Bytes Transmitted";
            }
            if( $option =~ /rx_b(ps|ytes)/  ) {
               $option_map{ "Rx Bytes" } = '';
               $option = "Bytes Rcvd";
            }
            if( $option =~ /tx_packets/) {
               $option_map{ "Tx Pkts" } = '';
               $option = "Packets Transmitted";
            }
            if( $option =~ /rx_packets/) {
               $option_map{ "Rx Pkts" } = '';
               $option = "Packets Rcvd";
            }

            $option_map{ $option } = '';
         }
         # options are reformatted

         my $i;
         my @lines         = split(NL, $::utils->doAsyncCmd("nc_show_endp $endp_name"));
         for($i=0; $i<@lines; $i++) {
            $lines[$i] = $lines[$i]." #";
         }
         my $matcher       = " (".join('|', keys %option_map)."):";
         my @parts;
         my @matches       = grep( /$matcher/, @lines);
         my $match;
         #print "MATCHER $matcher".NL;
         for my $end_val (split(',', $::endp_vals)) {
            my $endval_done = 0;
            for $match (@matches) {
               last if ($endval_done);
               #print "\nM: $end_val> $match\n";

               # no value between colon separated tags can be very
               # confusing to parse, let's force a dumb value in if we find that
               if ($match =~ /[^ ]+:\s+[^ ]+:/) {
                  $match =~ s/([^ ]+:)\s+([^ ]+:\s+)/$1 ""  $2/g;
                  #print "\n M> $match\n";
               }

               ## ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- #
               ##    special cases                                                  #
               ## ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- #
               if (  $match =~ /Rx (Bytes|Pkts)/ && $end_val =~ /rx_/) {
                  my $value = 0;
                  ($option) = ($match =~ /(Rx (Bytes|Pkts))/);
                  #print "Option: $option".NL;
                  @parts      = ($match =~ m{ Total: (\d+) +Time: \d+s\s+ Cur: (\d+) +(\d+)\/s \#$});
                  #print "\n RX: ".join(",",@parts)."\n";
                  if ( defined $option_map{ $option } ) {
                     if ($end_val =~ /rx_(bps|pps)/ ) {
                        $value = 0 + $parts[2];
                     }
                     elsif ($end_val =~ /rx_(byte|pkt|packet)s/ ) {
                        $value = 0 + $parts[0];
                     }
                     if ( $option eq "Rx Bytes") {
                        if ($end_val =~ /rx_bps/ ) {
                           $value   *= 8;
                        }
                     }
                     #print "\n    A end_val[$end_val] option[$option] now ".$value."\n";
                     $option_map{ $option } = $value;
                     $endval_done++;
                     last;
                  }
               }
               elsif (  $match =~ /Cx Detected/) {
                  my $value = 0;
                  ($option) = ($match =~ /(Cx Detected)/);
                  if ( defined $option_map{ $option } ) {
                     $value = 0 + ($match =~ /:\s+(\d+)/)[0];
                     $option_map{ $option } = $value;
                     $endval_done++;
                     last;
                  }
               }
               elsif (  $match =~ /Tx (Bytes|Pkts)/ && $end_val =~ /tx_/) {
                  my $value = 0;
                  ($option) = ($match =~ /(Tx (Bytes|Pkts))/);
                  #print "Option: $option".NL;
                  @parts      = ($match =~ m{ Total: (\d+) +Time: \d+s\s+ Cur: (\d+) +(\d+)\/s \#$});
                  #print "\n TX: ".join(",",@parts)."\n";
                  if ( defined $option_map{ $option } ) {
                     if ($end_val =~ /tx_(bps|pps)/ ) {
                        $value = 0 + $parts[2];
                     }
                     elsif ($end_val =~ /tx_(byte|pkt|packet)s/ ) {
                        $value = 0 + $parts[0];
                     }
                     if ($option eq "Tx Bytes") {
                        if ($end_val =~ /tx_bps/ ) {
                           $value   *= 8;
                        }
                     }
                     #print "\n    B end_val[$end_val] option[$option] now ".$value."\n";
                     $option_map{ $option } = $value;
                     $endval_done++;
                     last;
                  }
               }
               elsif (  $match =~ / [TR][Xx] (((OOO|Duplicate|Failed) (Bytes|Pkts))|Wrong Dev|CRC Failed|Bit Errors|Dropped)/
                     || $match =~ /Conn (Established|Timeouts)|TCP Retransmits/) {
                  my $value = 0;
                  ($option) = ($match =~ /([TR][Xx] (((OOO|Duplicate|Failed) (Bytes|Pkts))|Wrong Dev|CRC Failed|Bit Errors|Dropped)|Conn (Established|Timeouts)|TCP Retransmits)/);
                  @parts      = $match =~ m{ Total: (\d+) +Time: \d+s\s+ Cur: (\d+) +(\d+)\/s \#$};
                  #print "\n TX: ".join(",",@parts)."\n";
                  if ( defined $option_map{ $option } ) {
                     #print "$match\n";
                     $match =~ s/""/ /g;
                     ($option_map{ $option }) = $match =~/.*?:\s+(.*?)\s+\#$/;
                     $endval_done++;
                     last;
                  }
               }
               elsif (  $match =~ /(Bytes|Packets) (Rcvd|Transmitted)/ ) {
                  ($option) = ($match =~ /((Bytes|Packets) (Rcvd|Transmitted))/);
                  @parts      = ($match =~ m{ Total: (\d+) +Time: \d+s\s+ Cur: (\d+) +(\d+)\/s \#$});
                  my $value = 0;
                  if ( defined $option_map{ $option } ) {
                     if ($end_val =~ /rx_(bps|pps)/ ) {
                        $value = 0 + $parts[2];
                     }
                     elsif ($end_val =~ /rx_(byte|pkt|packet)s/ ) {
                        $value = 0 + $parts[0];
                     }
                     if ($option eq "Bytes Rcvd") {
                        if ($end_val =~ /rx_bps/ ) {
                           $value   *= 8;
                        }
                     }

                     #print "\n      C end_val[$end_val] option[$option] now ".$value."\n";
                     $option_map{ $option } = $value;
                     $endval_done++;
                     last;
                  }
               }
               else {
                  # special case
                  $match =~ s/Shelf: (\d+), /Shelf: $1  /
                     if ($match =~ /^\s*Shelf:/ );

                  $match =~ s/(Endpoint|PktsToSend): (\d+) /$1: $2  /
                     if ($match =~ /\s*(Endpoint|PktsToSend):/ );

                  if ($match =~ /((Src|Dst)Mac): /) {
                     my ($name1, $mac1) = ( $match =~ /(...Mac): (.*?)  /);
                     $mac1 =~ s/ /-/g;
                     $match =~ s/(...Mac): (.. .. .. .. .. ..) /$1: $mac1 /;
                  }
                  if ($match =~ /FileName: .*? SendBadCrc: /) {
                     my $filename1 = '';
                     ($filename1) =~ /FileName: (.*?) SendBadCrc.*$/;
                     $filename1 = '""' if ($filename1 =~ /^ *$/);
                     $match =~ s/(FileName): (.*?) (SendBadCrc.*)$/$1: $filename1  $3/;
                  }
                  $match =~ s/CWND: (\d+) /CWND: $1  /
                     if ($match =~/CWND: (\d+) /);
                  # ~specials

                  @parts         = ($match =~ m/( *[^ ]+):( *\S+ [^ #]*)(?! #|\S+:)/g);
                  for (my $i=0; $i < @parts; $i+=2) {
                     $option     = $parts[$i];
                     #print "     parts[$option] ";
                     $option     =~ s/^\s*(.*)\s*$/$1/;
                     if ( defined $option_map{ $option } ) {
                        my $value = $parts[ $i + 1 ];
                        if ($value =~ /^\s*([^ ]+):\s+/) {
                           $value   = "-";
                        }
                        else {
                           $value   =~ s/^\s*(.*)\s*$/$1/;
                        }
                        #print "\n      D end_val[$end_val] option[$option] now ".$value."\n";
                        $option_map{ $option } = $value;
                        $endval_done++;
                        last;
                     }
                  }
               }
            } # ~matches
         } # ~endp_vals
         for $option ( sort keys %option_map ) {
            print $option.": ".$option_map{ $option }.NL;
         }
      }
      else {
         print $::utils->doAsyncCmd("nc_show_endp $::endp_name");
      }
   }
   elsif ($::action eq "create_arm") {
      die("Must choose packets per second: --arm_pps\n$::usage")
         if (! defined $::arm_pps || $::arm_pps eq "");

      $::min_pkt_sz = "1472" if ($::min_pkt_sz eq "-1");
      $::max_pkt_sz = $::min_pkt_sz if ($::max_pkt_sz eq "-1");
      my $ip_port   = "-1"; # let lf choose
      $cmd = $::utils->fmt_cmd("add_arm_endp",   $::endp_name,  shelf_num,     $::resource,
                              $::port_name,     "arm_udp",     $::arm_pps,
                              $::min_pkt_sz,    $::max_pkt_sz, $::arm_cpu_id, $::tos);
      $::utils->doCmd($cmd);

      $cmd = "set_endp_report_timer $::endp_name $::report_timer";
      $::utils->doCmd($cmd);
   }
   elsif ($::action eq "create_endp") {
     die("Must choose endpoint protocol type: --endp_type\n$::usage")
         if (! defined $::endp_type|| $::endp_type eq "");

     $::endp_type  = "lf_tcp" if ($::endp_type eq "tcp");
     $::endp_type  = "lf_udp" if ($::endp_type eq "udp");

     die("Endpoint protocol type --endp_type must be among "
        .join(', ', @::known_endp_types)."\n".$::usage)
         if (! grep {$_ eq $::endp_type } @::known_endp_types);

     if ($::endp_type eq "generic") {
       if ($::endp_cmd eq "") {
	 die("Must specify endp_cmd if creating a generic endpoint.\n");
       }
       $cmd = $::utils->fmt_cmd("add_gen_endp",   $::endp_name,  shelf_num,     $::resource,
                                 $::port_name,  "gen_generic");
       $::utils->doCmd($cmd);

       # Create the dummy
       #my $dname = "D_" . $::endp_name;
       #$cmd = $::utils->fmt_cmd("add_gen_endp",   $dname,  shelf_num,     $::resource,
       #                          $::port_name,  "gen_generic");
       #$::utils->doCmd($cmd);

       $cmd = "set_gen_cmd " . $::endp_name . " " . $::endp_cmd;
       $::utils->doCmd($cmd);

       $cmd = "set_endp_report_timer $::endp_name $::report_timer";
       $::utils->doCmd($cmd);

       $::cx_name = "CX_" . $::endp_name;
       $cmd = "add_cx " . $::cx_name . " " . $::test_mgr . " " . $::endp_name;
       $::utils->doCmd($cmd);

       my $cxonly = NA;
       $cmd = $::utils->fmt_cmd("set_cx_report_timer", $::test_mgr, $::cx_name, $::report_timer, $cxonly);
       $::utils->doCmd($cmd);
     }
     elsif ($::endp_type eq "mc_udp") {
       # For instance:
       # add_endp mcast-xmit-eth1 1 3 eth1 mc_udp 9999 NO 9600 0 NO 1472 1472 INCREASING NO 32 0 0
       # set_mc_endp mcast-xmit-eth1 32 224.9.9.9 9999 NO
       # Assume Layer-3 for now

       $cmd = $::utils->fmt_cmd("add_endp",   $::endp_name,     shelf_num,     $::resource,
                                 $::port_name,  $::endp_type,     $::mcast_port, NA,
                                 "$::speed",    "$::max_speed",   NA,            $::min_pkt_sz,
                                 $::max_pkt_sz, "increasing",     $::use_csums,  "$::ttl", "0", "0");
       $::utils->doCmd($cmd);

       $cmd = $::utils->fmt_cmd("set_mc_endp", $::endp_name, $::ttl, $::mcast_addr, $::mcast_port, $::rcv_mcast);
       $::utils->doCmd($cmd);

       $cmd = "set_endp_report_timer $::endp_name $::report_timer";
       $::utils->doCmd($cmd);
     }
     elsif ( grep { $_ eq $::endp_type} split(/,/, "lf_udp,lf_tcp,lf_udp6,lf_tcp6")) {
        die("Which port is this? --port_name")
            if (!defined $::port_name || $port_name eq "" || $port_name eq "0" );

        die("Please set port speed: --speed")
            if ($::speed eq "-1"|| $::speed eq NA);

        if ($::min_pkt_sz =~ /^\s*auto\s*$/i) {
            $::min_pkt_sz = "-1";
        }
        if ($::max_pkt_sz =~ /^\s*same\s*$/i ) {
           $::max_pkt_sz = "0";
        }
        elsif ($::max_pkt_sz =~ /^\s*auto\s*$/i) {
           $::max_pkt_sz = "-1";
        }

        # Assume Layer-3 for now
        my $bursty    = NA;
        my $random_sz = NA;
        my $payld_pat = "increasing";
        $::ttl        = NA;
        my $bad_ppm   = "0";
        $cmd = $::utils->fmt_cmd("add_endp",   $::endp_name,  shelf_num,   $::resource,
                                 $::port_name,  $::endp_type,  $::ip_port,   $bursty,
                                 $::speed,      $::max_speed,
                                 $random_sz,    $::min_pkt_sz, $::max_pkt_sz,
                                 $payld_pat,    $::use_csums,  $::ttl,
                                 $bad_ppm,      $::multicon);
        $::utils->doCmd($cmd);

        $cmd = "set_endp_report_timer $::endp_name $::report_timer";
        $::utils->doCmd($cmd);

        if ($::tos ne "") {
           my($service, $priority) = split(',', $::tos);
           $::utils->doCmd($::utils->fmt_cmd("set_endp_tos", $::endp_name, $service, $priority));
        }
     }
     else {
       die( "ERROR:  Endpoint type: $::endp_type is not currently supported.");
     }
   }
   else {
      # Set endp
      if ($speed ne "NA") {
         # Read the endpoint in...
	 #my $endp1 = new LANforge::Endpoint();
         #$::utils->updateEndpoint($endp1, $endp_name);

         # Assume Layer-3 for now
         $cmd = $::utils->fmt_cmd("add_endp", $endp_name, NA, NA, NA, NA, NA, NA, $speed,  $max_speed);
	 print("cmd: $cmd\n");
         $::utils->doCmd($cmd);
      }
   }
}
elsif ($::action eq "start_endp") {
   $cmd = "start_endp $::endp_name";
   $::utils->doCmd($cmd);
}
elsif ($::action eq "stop_endp") {
   $cmd = "stop_endp $::endp_name";
   $::utils->doCmd($cmd);
}
elsif ($::action eq "delete_endp") {
   $cmd = "rm_endp $::endp_name";
   $::utils->doCmd($cmd);
}
elsif ($::action eq "show_port") {
  print $::utils->doAsyncCmd("nc_show_port 1 $::resource $::port_name") . "\n";
}
elsif ($::action eq "do_cmd") {
  print $::utils->doAsyncCmd("$::do_cmd") . "\n";
}
elsif ($::action eq "list_ports") {
  my @ports = $::utils->getPortListing(shelf_num, $::resource);
  my $i;
  for ($i = 0; $i<@ports; $i++) {
    my $cur = $ports[$i]->cur_flags();
    #print "cur-flags -:$cur:-\n";

    print $ports[$i]->dev();
    if ($cur =~ /LINK\-UP/) {
      print " link=UP";
    }
    else {
      print " link=DOWN";
    }
    # Guess speed..need better CLI output API for more precise speed.
    if ($cur =~ /10G\-FD/) {
      print " speed=10G";
    }
    elsif ($cur =~ /1000\-/) {
      print " speed=1G";
    }
    elsif ($cur =~ /100bt\-/) {
      print " speed=100M";
    }
    elsif ($cur =~ /10bt\-/) {
      print " speed=10M";
    }
    else {
      print " speed=UNKNOWN";
    }
    print "\n";
  }
}
elsif ($::action eq "list_cx") {
   $::cx_name  = $::list_cx_name    if ($::cx_name  eq "");
   $::test_mgr = $::list_test_mgr   if ($::test_mgr eq "");

   my $cmd = $::utils->fmt_cmd("show_cxe", $::test_mgr, $::cx_name );
   my @lines = split(NL, $::utils->doAsyncCmd($cmd));
   my $out = '';
   my $num_ep = 0;
   for my $line (@lines) {
      #print "      |||$line\n";
      if ($line =~ /\s*WAN_LINK CX:\s+([^ ]+)\s+id:.*$/ ) {
         $out .= "WL $1";
      }
      if ($line =~ /^WanLink\s+\[([^ ]+)\] .*$/ ) {
         $out .= ", wanlink $1";
         $num_ep++;
      }
      if ($line =~ /^\s*(WanLink|LANFORGE.*? CX):\s+([^ ]+) .*$/ ) {
         $out .= "CX $2";
      }
      if ($line =~ /^ARM_.*? CX:\s+([^ ]+) .*$/ ) {
         $out .= "CX $1";
      }
      if ($line =~ /^(Endpoint|ArmEndp) \[([^ \]]+)\].*$/) {
         $out .= ", endpoint $2";
         $num_ep++;
      }
      if (($line =~ /^ *$/) && ($num_ep >1)) {
         print "$out\n";
         $out = '';
         $num_ep = 0;
      }
   }
}
elsif ($::action eq "show_cx") {
   # require a cx_name
   die("Please specify cx_name\n$::usage") if (length($::cx_name) < 1);
   if (length($::test_mgr) <1) {
      $::test_mgr = "default_tm";
   }
   my $cmd = $::utils->fmt_cmd("show_cxe", $::test_mgr, $::cx_name );
   print $::utils->doAsyncCmd($cmd)."\n";
}
elsif ($::action eq "create_cx") {
   # require cx_name, test_mgr, two endpoints
   die("Please name your cross connect: --cx_name\n$::usage")  if ($::cx_name  eq "");
   die("Please name two endpoints: --cx_endps\n$::usage")      if ($::cx_endps eq "");

   my ($end_a, $end_b) = split(/,/, $::cx_endps);
   die("Specify two endpoints like: eth1,eth2 \n$::usage")
      if ((length($end_a) < 1) || (length($end_b) < 1));

   my $cmd = $::utils->fmt_cmd("add_cx", $::cx_name, $::test_mgr, $end_a, $end_b);
   $::utils->doCmd($cmd);
   my $cxonly = NA;
   $cmd = $::utils->fmt_cmd("set_cx_report_timer", $::test_mgr, $::cx_name, $::report_timer, $cxonly);
   $::utils->doCmd($cmd);
}
elsif ($::action eq "delete_cx") {
   # require cx_name
   die("Which test manager?: --test_mgr\n$::usage") if ($::test_mgr eq "");
   die("Which cross connect? --cx_name\n$::usage")  if ($::cx_name eq "");
   $::utils->doCmd($::utils->fmt_cmd("rm_cx", $::test_mgr, $::cx_name));
}
else {
  die("Unknown action: $::action\n$::usage\n");
}

exit(0);