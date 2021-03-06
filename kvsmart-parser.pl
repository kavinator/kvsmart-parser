#!/usr/bin/env perl
# Copyright (c) 2012-2015 Vladimir Petukhov (kavinator@gmail.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

kvsmart-parser.pl

=head1 SYNOPSIS

kvsmart-parser -- simple S.M.A.R.T. parser with the account of the hard disk vendors

=cut

use strict;
use warnings;

use 5.010;
use File::Path;
use Getopt::Long;

my $VERSION = '0.5.5';

my $SMARTCTL_BIN = '/usr/sbin/smartctl';
my $SEP_OUTPUT   = "\t";
my $LOG_PATH     = '';

my $VER;
my $HELP;
my $DEBUG;
my @DRIVES;
my @VENDORS;
my @ATTRIBUTES;

=head1 DESCRIPTIONS

...

=cut

# TODO: remove smartmatch: Smartmatch is experimental now

my $COPYRIGHT = "kvsmart-parser $VERSION Copyright (c) 2012-2015 Vladimir Petukhov (kavinator\@gmail.com)";

GetOptions(
    'drives|drv=s{,}'    => \@DRIVES,
    'vendors|ven=s{,}'   => \@VENDORS,
    'smart-attr|sa=s{,}' => \@ATTRIBUTES,
    'sep-output|so=s'    => \$SEP_OUTPUT,
    'log-path|lp=s'      => \$LOG_PATH,
    'debug|d'            => \$DEBUG,
    'version|v'          => \$VER,
    'help|h'             => \$HELP,
) or die "Incorrect usage!\n";

################################################################################
# MAIN PART
################################################################################

if ( $HELP or $#ARGV == 0 )
{
    print_usage();
    exit 0;
}
elsif ( $VER )
{
    print "$COPYRIGHT\n";
    exit 0;
}

if ( $ENV{ USER } ne 'root' )
{
    print_error(
        'root privileges are required to detect vendor or run smartctl!',
        'warning'
    );
}

unless ( -x $SMARTCTL_BIN )
{
    print "\nERROR: cannot find smartctl\n\n";
    exit 0;
}

@DRIVES = vendor_check(
    [ drives_check( @DRIVES ) ],
    \@VENDORS
);

@ATTRIBUTES = smart_attr_check( \@ATTRIBUTES )
    if @ATTRIBUTES;

for my $drive ( @DRIVES )
{
    print_debug_if_required( "use $drive" );
    my $drive_smart = run_smart( $drive );
    if ( %$drive_smart )
    {
        $drive =~ m{/dev/(\w+)};
        my @smart_log  = ();
        my $attributes = [ keys %$drive_smart ];
        if ( @ATTRIBUTES )
        {
            @$attributes =
                grep{ $_ if $_ ~~ @ATTRIBUTES }
                @$attributes;
            push @$attributes, 'ATTRIBUTE_NAME';
        }
        for my $attr ( sort @$attributes )
        {
            my %attr_data = %{ $drive_smart->{ $attr } };
            # order of smart-data colums
            my $columns = [ qw( id flag value worst thresh type updated fail raw_value ) ];
            my $values  = [
                grep{ defined }
                @attr_data{ @$columns }
            ];
            push @smart_log, join( $SEP_OUTPUT, $drive, $attr, @$values ) . "\n";
        }
        if ( $LOG_PATH )
        {
            log_write(
                "$LOG_PATH/$1.log",
                \@smart_log,
            );
        }
        else
        {
            print @smart_log;
        }
    }
}

################################################################################
# FUNCTIONS
################################################################################

=head1 FUNCTIONS

=over 1

=item print_usage()

...

=cut

sub print_usage
{
    print "$COPYRIGHT
Usage: $0 [ OPTIONS ] [ VENDORS ] [ LOGPATH ] ... -drv='DRIVES'

OPTIONS:
    -drv, --drives='/dev/hda [, /dev/hdb [...] ]'
        $0 --drives='/dev/hda'
        $0 --drives='/dev/hda, /dev/hdb'

    -ven, --vendors='vendor1 [, vendor2 [...] ]'
        $0 --drives='/dev/hda' --vendors='VENDER'
        $0 --drives='/dev/hda' --vendors='VENDER0, VENDER1'

    -sa, --smart-attr='attr1 [, attr2 [...] ]'
        $0 --drives='/dev/hda' --smart-attr='Spin_Up_Time'
        $0 --drives='/dev/hda' --smart-attr='Spin_Up_Time, Temperature_Celsius'

    -so, --sep-output='SEPARATOR'
        separator of output in a rows
        default: '\t' (tab)
        $0 --drives='/dev/hda' --sep-output=';'
        $0 --drives='/dev/hda' --sep-output=','

    -lp, --log-path='/path/path'
        write output in log-directory
        $0 --drives='/dev/hda' --log-path='/var/log/kvsmart-parser'

    -d, --debug
        use debug mode
        $0 --drives='/dev/hda' --debug

    -h, --help
        show help
        $0 --drives='/dev/hda' --help

    -v, --version
        print version
        $0 --drives='/dev/hda' --version

This program comes with ABSOLUTELY NO WARRANTY. This is free software,
and you are welcome to redistribute it under terms and conditions of the
GNU General Public License as published by the Free Software Foundation;
either version 3 of the License, or (at your option) any later version.
";
    return;
}

=item print_error()

print_error( $error_message, $error_type )

=cut

sub print_error
{
    my $msg  = shift;
    my $type = shift || 'error';
    $type =~ s/(.*)/\U$1/g;
    print "$type: $msg\n";
    return;
}

=item print_debug_if_required()

...

=cut

sub print_debug_if_required
{
    print "$_[0]\n"
        if $DEBUG;
    return;
}

=item file_read()

file_read( $file_name )
@return: ref to array

=cut

sub file_read
{
    my $file_name = shift;
    my $output = [];
    open my $IN, '<', $file_name
        or die print_error( "Can't open file: $!" );
        @$output = <$IN>;
    close $IN
        or die print_error( "Can't close file: $!" );
    return $output;
}

=item log_write()

log_write( $file_name, @array )

=cut

sub log_write
{
    my $file_name = shift;
    my $log_data  = shift;
    my $file_path = ( $file_name =~ /^(.*\/).*?$/ )
        ? $1
        : './';
    mkpath(
        $file_path,
        { error => \my $errmsg }
    );
    if ( @$errmsg )
    {
        for my $diag ( @$errmsg )
        {
            my ( $file, $message ) = %$diag;
            if ( $file eq '' )
            {
                print_error( "general error: $message" );
            }
            else
            {
                print_error( "create $file: $message" );
            }
        }
    }
    if ( -e $file_name )
    {
        print_debug_if_required( "file \"$file_name\" exist, replaced" );
        unlink $file_name;
    }
    print_debug_if_required( "write log to \"$file_name\"");
    open my $OUT, '>>', $file_name
        or die print_error( "Can't write file: $!" );
        print $OUT map{ $_ } @$log_data;
    close $OUT
        or die print_error( "Can't close file: $!" );
    return;
}

=item split_names()

split_names( @names )
@return array

=cut

sub split_names
{
    my @names =
        grep{ defined }
        split(
            /[,\ ]\s*/,
            join( ',', @_ ),
        );

    return @names;
}

=item drives_check()

drives_check( @drives )
@return array of checked drives

=cut

sub drives_check
{
    my @drives = @_;
    my @rigth_drives;

    foreach my $drive_name ( split_names( @drives ) )
    {
        my ( $drive_file ) = $drive_name =~ m{^\s*(/dev/.+)\s*?$};
        if ( -e $drive_file )
        {
            print_debug_if_required( "\"$drive_file\" exist" );
            push @rigth_drives, $drive_file;
        }
        else
        {
            print_error(
                "drive \"$drive_file\" not exist",
                "warning",
            );
        }
    }
    print_debug_if_required(
        "Detected drives: ",
        join( ', ', @rigth_drives ),
    );

    return @rigth_drives;
}

=item vendor_check()

vendor_check( @drives )
@return: ref to array

=cut

sub vendor_check
{
    my $drives  = shift;
    my $vendors = shift;
    unless ( @$vendors )
    {
        return @$drives;
    }
    else
    {
        @$vendors = split_names( @$vendors );
        print_debug_if_required( "Detected vendors: " . join( ', ', @$vendors ) );
        my $right_drives = [];
        for my $drive ( @$drives )
        {
            $drive =~ m{/dev/([a-zA-Z0-9_]+)};
            my $model_path = "/sys/block/$1/device/model";
            if ( -r "$model_path" )
            {
                my $vendor = ( split /\s+/, @{ file_read( $model_path ) }[0] )[0];
                print_debug_if_required( "drive \"$drive\" vendor \"$vendor\"" );
                push @$right_drives, $drive
                    if $vendor ~~ @$vendors;
            }
        }
        return @$right_drives;
    }
}

=item smart_attr_check()

smart_attr_check( @attributes )

=cut

sub smart_attr_check
{
    my $attributes = shift;
    if ( @$attributes )
    {
        $attributes = [ split_names( @$attributes ) ];
        print_debug_if_required( "Detected SMART attributes: " . join( ', ', @$attributes ) );
    }
    return @$attributes;
}

=item run_smart()

smart_data => (
    'Spin_Up_Time' => (
        raw_value => 3300,
        type => 'Pre-fail'
        thresh => 021,
        value => '234',
        worst => '233',
    ),
    'Temperature_Celsius' => (
        raw_value => 34,
        type => 'Old_age'
        thresh => 000,
        value => '116',
        worst => '105',
    ),
)

run_smart( $drive_name )
@return: ref to hash

=cut

sub run_smart
{
    my $drive = shift;
    my $cmd = "$SMARTCTL_BIN --attributes $drive";
    print_debug_if_required( "run smartctl for $drive" );
    my $smart_result = [ `$cmd` ];
    my $found_start_tag;
    my $errmsg = "";
    for ( @$smart_result )
    {
        chomp;
        if ( /^ID#\s+ATTRIBUTE_NAME\s+FLAG/ )
        {
            $found_start_tag = 1;
            last;
        }
        if ( /Permission denied/ )
        {
            $errmsg = $_;
            last;
        }
        if ( /command not found/ )
        {
            $errmsg = "command error: $_";
            last;
        }
        if ( /SMART support is: Unavailable/ )
        {
            $errmsg = $_;
            last;
        }
        if ( /open device: .* failed/ )
        {
            $errmsg = $_;
            last;
        }
        if ( /\[this device: CD\/DVD\]/ )
        {
            $errmsg = "device is a CD/DVD drive.";
            last;
        }
        if ( /^Smartctl: Device Read Identity Failed \(not an ATA\/ATAPI device\)/ )
        {
            $errmsg = "device does not exist.";
            last;
        }
        if ( /Unable to detect device type/ )
        {
            $errmsg = $_;
            last;
        }
    }
    if ( $errmsg eq "" && !$found_start_tag )
    {
        $errmsg = "parse error, no param start tag found!";
    }
    if ( $errmsg )
    {
        print_error( $errmsg );
        exit;
    }
    my %smart_data;
    for ( @$smart_result )
    {
        if ( /^\s*(?:\d{1,3}|ID#)\s+.*?$/ )
        {
            chomp;

            # TODO: remove brief-format parsing

            # Example of smartctl output for ATA-drive (old-format)
            # ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
            #   9 Power_On_Hours          0x0032   096   096   000    Old_age   Always       -       3404
            #  12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       408
            # 194 Temperature_Celsius     0x0022   116   097   000    Old_age   Always       -       31
            #
            # Example of smartctl output for ATA-drive (brief-format)
            # ID# ATTRIBUTE_NAME          FLAGS    VALUE WORST THRESH FAIL RAW_VALUE
            #   9 Power_On_Hours          -O--CK   099   099   000    -    1078
            #  12 Power_Cycle_Count       -O--CK   100   100   000    -    497
            # 194 Temperature_Celsius     -O---K   117   105   000    -    33
            #                             ||||||_ K auto-keep
            #                             |||||__ C event count
            #                             ||||___ R error rate
            #                             |||____ S speed/performance
            #                             ||_____ O updated online
            #                             |______ P prefailure warning

            m(
                ^\s*?
                (?<id>[0-9]{1,3}|ID\#)\s+          # number  or 'ID#'
                (?<attr_name>[a-zA-Z0-9_-]+)\s+    # wo-rd_
                (?<flag>[a-zA-Z0-9_-]+)\s+         # wo-rd_  or 'FLAG' or 'FLAGS'
                (?<value>[0-9-]+|VALUE)\s+         # num-ber or 'VALUE'
                (?<worst>[0-9-]+|WORST)\s+         # num-ber or 'WORST'
                (?<thresh>[0-9-]+|THRESH)\s+       # num-ber or 'THRESH'
                (?<old_format>
                    (?<type>[a-zA-Z0-9_-]+)\s+     # wo-rd_  or 'TYPE'
                    (?<updated>[a-zA-Z0-9_-]+)\s+  # wo-rd_  or 'UPDATED'
                )?
                (?<fail>[a-zA-Z0-9_-]+)\s+         # wo-rd_  or 'WHEN_FAILED' or 'FAIL'
                (?<raw_value>[0-9-]+|RAW_VALUE)    # num-ber or 'RAW_VALUE'
                \s*$
            )x;

            unless ( $+{ attr_name } ~~ %smart_data )
            {
                $smart_data{ $+{ attr_name } } = {
                    id        => $+{ id },
                    flag      => $+{ flag },
                    value     => $+{ value },
                    worst     => $+{ worst },
                    thresh    => $+{ thresh },
                    fail      => $+{ fail },
                    raw_value => $+{ raw_value },
                };
                if ( $+{ old_format } )
                {
                    for my $section ( qw( type updated ) )
                    {
                        $smart_data{ $+{ attr_name } }{ $section } = $+{ $section }
                            if $+{ $section };
                    }
                }
            }
        }
    }
    return \%smart_data;
}
