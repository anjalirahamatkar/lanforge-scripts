#!/usr/bin/perl -w
# This script tests scripts
use strict;
use warnings;
use diagnostics;
use Carp;

$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };
$SIG{ __WARN__ } = sub { Carp::confess( @_ ) };
$| = 1;

use Net::Telnet;
use lib '.';
use lib './LANforge';
# Ubuntu: libtry-tiny-smartcatch-perlq
use Try::Tiny;
use Getopt::Long;
use JSON::XS;
use HTTP::Request;
use LWP;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
# Ubuntu: libtest2-suite-perl
use Test2::V0 qw(ok fail done_testing);
use Test2::Tools::Basic qw(plan);

use constant NA => "NA";
use LANforge::Utils;
use LANforge::Port;
use LANforge::Endpoint;
use LANforge::JsonUtils qw(err logg xpand json_request get_links_from get_thru json_post get_port_names flatten_list);
use LANforge::Test qw(new test run);
#our $PASS = $LANforge::Test::PASS;
#our $FAIL = $LANforge::Test::FAIL;

package main;
our $LFUtils;
our $lfmgr_host       = "ct524-debbie";
our $lfmgr_port       = 4001;
our $http_port        = 4001;
our $resource         = 1;
our $quiet            = 1;
our @specific_tests   = ();
our %test_subs        = ();
our $lf_mgr           = undef;
our $HostUri          = undef;
our $Web              = undef;
our $Decoder          = undef;
#our @test_errs        = ();
my $help              = 0;
my $list              = 0;
my $usage = qq($0 --mgr {lanforge hostname/IP}
  --mgr_port|p {lf socket (4001)}
  --resource|r {resource number (1)}
  --quiet {0,1,yes,no}
  --test|t {test-name} # repeat for test names
  --list|l # list test names
);

GetOptions (
   'mgr|m=s'            => \$::lfmgr_host,
   'mgr_port|p:s'       => \$::lfmgr_port,
   'card|resource|r:i'  => \$resource,
   'quiet|q:s'          => \$quiet,
   'test|t:s'           => \@specific_tests,
   'help|h'             => \$help,
   'list|l'             => \$list,
) || (print($usage) && exit(1));

if ($help) {
  print($usage) && exit(0);
}

our %tests = ();

$lf_mgr = $lfmgr_host;
$::HostUri   = "http://$lf_mgr:$http_port";
$::Web       = LWP::UserAgent->new;
$::Decoder   = JSON->new->utf8;

my $telnet = new Net::Telnet(Prompt => '/default\@btbits\>\>/',
                       Timeout => 20);
$telnet->open(Host    => $::lf_mgr,
        Port    => $::lfmgr_port,
        Timeout => 10);
$telnet->waitfor("/btbits\>\>/");
$::LFUtils = new LANforge::Utils();
$::LFUtils->telnet($telnet);         # Set our telnet object.
if ($::LFUtils->isQuiet()) {
 if (defined $ENV{'LOG_CLI'} && $ENV{'LOG_CLI'} ne "") {
   $::LFUtils->cli_send_silent(0);
 }
 else {
   $::LFUtils->cli_send_silent(1); # Do not show input to telnet
 }
 $::LFUtils->cli_rcv_silent(1);  # Repress output from telnet
}
else {
 $::LFUtils->cli_send_silent(0); # Show input to telnet
 $::LFUtils->cli_rcv_silent(0);  # Show output from telnet
}

our $port_ip = "";

#----------------------------------------------------------------------
#   Tests
#----------------------------------------------------------------------


#----------------------------------------------------------------------
# multiple ways of querying a port:
# * CLI
# * Port.pm
# * JSON
# * shell out to perl script
#----------------------------------------------------------------------
$tests{'query_port_cli'} = LANforge::Test->new(Name=>'query_port_cli',
   Desc=>'query port using cli', Test => sub{
     my $self = pop;
     my $cmd = $::LFUtils->fmt_cmd("nc_show_port", 1, $::resource, "eth0");
     my $resp = $::LFUtils->doAsyncCmd($cmd);
     ($::port_ip) = $resp =~ / IP:\s+([^ ]+) /;
     fail($self->{Name}) if (!(defined $::port_ip));
     $self->run((length($::port_ip) >= 7));
     # || fail($self->{Name}."port_ip [$::port_ip] incorrect\n");
   });

## test LANforge::Port
$tests{'query_port_class_port'} = LANforge::Test->new(Name=>'query_port_class_port',
   Desc=>'query port using class Port', Test=>sub {
     my $self = pop;
     my $cmd = $::LFUtils->fmt_cmd("nc_show_port", 1, $::resource, "eth0");
     my $resp = $::LFUtils->doAsyncCmd($cmd);
     my $lf_port = LANforge::Port->new;
     $lf_port->decode($resp);
     $self->run($lf_port->ip_addr() eq $::port_ip);
     
     #$self->test_err( "port_ip ".$lf_port->ip_addr()." doesn't match above $::port_ip");
     #return $LANforge::Test::FAIL;
   });

## test JsonUtils/port
$tests{'query_port_jsonutils'} = LANforge::Test->new(Name=>'query_port_jsonutils',
   Desc=>'query port using jsonutils', Test=>sub {
      my $self = pop;
      my $url = "http://".$::lf_mgr.":8080/port/1/1/eth0";
      my $port_json = json_request($url);
      #print Dumper($port_json);
      $self->run($port_json->{interface}->{ip} eq $::port_ip);
   });

## test lf_portmod.pl
$tests{'query_port_lfportmod'} = LANforge::Test->new(Name=>'query_port_lfportmod',
   Desc=>'query port using lfportmod', Test=>sub {
      my $self = pop;
      print "Trying: ./lf_portmod.pl --manager $::lf_mgr --card $::resource --port_name eth0 --show_port\n";
      fail("lf_portmod.pl not found in ".cwd()) if (-f "./lf_portmod.pl");
      my $resp = `./lf_portmod.pl --manager $::lf_mgr --card $::resource --port_name eth0 --show_port`;
      fail(!(defined $resp));
      #$self->test_err("Insufficient output from lf_portmod.pl.\n");

      my ($port_ip2) = $resp =~ / IP:\s+([^ ]+) /;
      $self->run((defined $port_ip2) && length($port_ip2) >= 7);
      #$self->test_err("port_ip [$port_ip2] incorrect\n");
      #return $::FAIL;
   });

$tests{'port_down_up_down_cli'} = LANforge::Test->new(Name=>'t_set_port_up',
   Desc=>'port_down_up_down, cli', Test=>sub {
     my $self = pop;
     my $up = 1;
     my $down = 0;
     my $report_timer = 1;
     my $status = -1;
     my $cmd = $::LFUtils->fmt_cmd("set_port", 1, $::resource, "eth1",
       NA, NA, NA, NA, $down, NA, NA, NA, NA, 8421378, $report_timer);
     my $resp = $::LFUtils->doAsyncCmd($cmd);
     my $begin = time();
     until ($status == $down) {
       sleep 1;
       $resp = $::LFUtils->doAsyncCmd("nc_show_port 1 $resource eth1");
       my @lines = split("\n", $resp);
       my @matching = grep { /^\s+Current:\s+/ } @lines;
       fail("eth1 has multiple lines starting with Current")
        if (@matching > 1);
       my ($updown) = $matching[0] =~ /Current:\s+(\w+)\s+/;
       $status = ($updown eq "UP") ? 1: (($updown eq "DOWN") ? 0 : -1);
       print $matching[0] 
        if ($status == -1);
       if ((time() - $begin) > 15) {
           fail("port does not report down in 15 seconds");
           die("stupid thing wont admin down");
       }
     }
     print "Port is down\n";
     ok(1);
     sleep 1;
     $cmd = $::LFUtils->fmt_cmd("set_port", 1, $::resource, "eth1",
       NA, NA, NA, NA, $up, NA, NA, NA, NA, 8421378, $report_timer);
     $resp = $::LFUtils->doAsyncCmd($cmd);
     $begin = time();
     until ($status == $up) {
       sleep 1;
       $resp = $::LFUtils->doAsyncCmd("nc_show_port 1 $resource eth1");
       my @lines = split("\n", $resp);
       my @matching = grep { /^\s+Current:\s+/ } @lines;
       fail("eth1 has multiple lines starting with Current") 
        if (@matching > 1);
       my ($updown) = $matching[0] =~ /Current:\s+(\w+)\s+/;
       $status = ($updown eq "UP") ? 1: (($updown eq "DOWN") ? 0 : -1);
       print $matching[0] 
        if ($status == -1);
       if ((time() - $begin) > 15) {
           fail("port does not report up in 15 seconds");
           die("stupid thing wont admin up");
       }
     }
     print "Port is up\n";
     ok(1);
     $cmd = $::LFUtils->fmt_cmd("set_port", 1, $::resource, "eth1",
       NA, NA, NA, NA, $down, NA, NA, NA, NA, 8421378, $report_timer);
     $resp = $::LFUtils->doAsyncCmd($cmd);
     $begin = time();
     until ($status == $down) {
       sleep 1;
       $resp = $::LFUtils->doAsyncCmd("nc_show_port 1 $resource eth1");
       my @lines = split("\n", $resp);
       my @matching = grep { /^\s+Current:\s+/ } @lines;
       fail("eth1 has multiple lines starting with Current") 
        if (@matching > 1);
       my ($updown) = $matching[0] =~ /Current:\s+(\w+)\s+/;
       $status = ($updown eq "UP") ? 1: (($updown eq "DOWN") ? 0 : -1);
       print $matching[0] 
        if ($status == -1);
       if ((time() - $begin) > 15) {
           fail("port does not report down in 15 seconds");
           die("stupid thing wont admin down");
       }
     }
     print "Port is down\n";
     ok(1);
   });

$tests{'port_up_class_port'} = LANforge::Test->new(Name=>'t_set_port_up',
   Desc=>'set port up, cli', Test=>sub {
   my $self = pop;
   #my $cmd = 
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
   });

sub t_set_port_down {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_create_mvlan {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_destroy_mvlan {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_query_radio {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_del_all_stations {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_add_station_to_radio {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_station_up {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_station_down {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_remove_radio {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_add_sta_L3_udp {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_sta_L3_start {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_sta_L3_stop {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

sub t_rm_sta_L3 {
  ## test CLI
  ## test LANforge::Port
  ## test JsonUtils/port
  ## test lf_portmod.pl
}

#----------------------------------------------------------------------
#----------------------------------------------------------------------
our @test_list = (
 'query_port_cli',
 'query_port_class_port',
 'query_port_jsonutils',
 'query_port_lfportmod',
  
  #'03_set_port_down'          => 0,
  #'04_create_mvlan'           => 0,
  #'05_destroy_mvlan'          => 0,
  #'06_query_radio'            => 0,
  #'07_del_all_stations'       => 0,
  #'08_add_station_to_radio'   => 0,
  #'09_station_up'             => 0,
  #'10_station_down'           => 0,
  #'11_remove_radio'           => 0,
  #'12_add_sta_L3_udp'         => 0,
  #'13_sta_L3_start'           => 0,
  #'14_sta_L3_stop'            => 0,
  #'15_rm_sta_L3'              => 0,
);


sub RunTests {
    my $rf_test = undef;
    
    #if (@specific_tests > 0) {
    #    for my $test_name (sort @specific_tests) {
    #        if (defined &{$::test_subs{$test_name}}) {
    #          test_err("Failed on $test_name") unless &{$::test_subs{$test_name}}();
    #        }
    #        else {
    #          test_err( "test $test_name not found");
    #        }
    #    }
    #}
    #else {
    plan(0+@::test_list);
    for my $test_name (@::test_list) {
      if (! (defined $::tests{$test_name})) {
         die("test $test_name not found");
      }
      my $r_test = $::tests{$test_name};
      try {
        print "$test_name...";
        my $rv = $r_test->test();
        print "$rv\n";
      }
      catch {
        $r_test->test_err($_);
      }
    }
  #}
}

# ====== ====== ====== ====== ====== ====== ====== ======
#   M A I N
# ====== ====== ====== ====== ====== ====== ====== ======

if ($list) {
  my $av="";
  print "Test names:\n";
  for my $test_name (@::test_list) {
      $av=" ";
      if (defined &{$::tests{$test_name}}) {
         $av='*';
      }
      print " ${av} ${test_name}\n";
  }
  exit(0);
}
else {
  RunTests();
}
done_testing();
#if (@test_errs > 1) {
#  print "Test errors:\n";
#  print join("\n", @::test_errs);
#}
print "\ndone\n";
#