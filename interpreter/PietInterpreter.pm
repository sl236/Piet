package Piet::Interpreter;

use 5.6.0;   #  or so.
use strict;
use Carp;
use Image::Magick;

our $VERSION = '0.03';

=head1 NAME

Piet::Interpreter - Interpreter for the Piet programming language

=head1 SYNOPSIS

    use Piet::Interpreter;

    my $p = Piet::Interpreter->new(image => 'my_code.gif');

    $p->run;

=head1 DESCRIPTION

Piet is a programming language in which programs look like abstract
paintings. The language is named after Piet Mondrian, who pioneered
the field of geometric abstract art.  The language is fully described
at http://www.physics.usyd.edu.au/~mar/esoteric/piet.html.  A Piet
program is an image file, usually a gif, which uses a set of 20 colors
and the transitions between blocks of those colors to define a series
of instructions and program flow.  See the above URL for more details.
(Note: some sample programs there may not work, as they were
constructed before a working interpreter was available.)

Since Piet is a visual language, an image parsing mechanism is
required.  This module uses Image::Magick, so it would be to your
advantage to download, install, and test that module and its
related stuff before trying to use this one.  

=cut

#  Initialize variables and lookup hashes

$| = 1;     #  buffer bad.

my $HEX_BLACK  = '000000';
my $HEX_WHITE  = 'FFFFFF';

my %hex2color  = ( 'FFC0C0' => 'light red',        'FFFFC0' => 'light yellow',
		   'C0FFC0' => 'light green',      'C0FFFF' => 'light cyan',
		   'C0C0FF' => 'light blue',       'FFC0FF' => 'light magenta',
		   'FF0000' => 'red',              'FFFF00' => 'yellow',
		   '00FF00' => 'green',	           '00FFFF' => 'cyan',
		   '0000FF' => 'blue',             'FF00FF' => 'magenta',
		   'C00000' => 'dark red',         'C0C000' => 'dark yellow',
		   '00C000' => 'dark green',       '00C0C0' => 'dark cyan',
		   '0000C0' => 'dark blue',        'C000C0' => 'dark magenta',
		   'FFFFFF' => 'white',	           '000000' => 'black',
		   );

my %hex2abbr   = ( 'FFC0C0' => 'lR', 'FFFFC0' => 'lY', 'C0FFC0' => 'lG',
		   'C0FFFF' => 'lC', 'C0C0FF' => 'lB', 'FFC0FF' => 'lM',
		   'FF0000' => ' R', 'FFFF00' => ' Y', '00FF00' => ' G',
		   '00FFFF' => ' C', '0000FF' => ' B', 'FF00FF' => ' M',
		   'C00000' => 'dR', 'C0C000' => 'dY', '00C000' => 'dG',
		   '00C0C0' => 'dC', '0000C0' => 'dB', 'C000C0' => 'dM',
		   'FFFFFF' => 'Wt', '000000' => 'Bk',
		   );

my %hex2hue    = ( 'FFC0C0' => 0, 'FFFFC0' => 1, 'C0FFC0' => 2,
		   'C0FFFF' => 3, 'C0C0FF' => 4, 'FFC0FF' => 5,
		   'FF0000' => 0, 'FFFF00' => 1, '00FF00' => 2,
		   '00FFFF' => 3, '0000FF' => 4, 'FF00FF' => 5,
		   'C00000' => 0, 'C0C000' => 1, '00C000' => 2,
		   '00C0C0' => 3, '0000C0' => 4, 'C000C0' => 5,
		   'FFFFFF' => -1, '000000' => -1,
		   );

my %hex2light  = ( 'FFC0C0' => 0, 'FFFFC0' => 0, 'C0FFC0' => 0,
		   'C0FFFF' => 0, 'C0C0FF' => 0, 'FFC0FF' => 0,
		   'FF0000' => 1, 'FFFF00' => 1, '00FF00' => 1,
		   '00FFFF' => 1, '0000FF' => 1, 'FF00FF' => 1,
		   'C00000' => 2, 'C0C000' => 2, '00C000' => 2,
		   '00C0C0' => 2, '0000C0' => 2, 'C000C0' => 2,
		   'FFFFFF' => -1, '000000' => -1,
		   );

my @do_arr = (
	      [ 'do_noop',      'do_push',     'do_pop' ],
	      [ 'do_add',       'do_subtract', 'do_multiply' ],
	      [ 'do_divide',    'do_mod',      'do_not' ],
	      [ 'do_greater',   'do_pointer',  'do_switch' ],
	      [ 'do_duplicate', 'do_roll',     'do_in_n' ],
	      [ 'do_in_c',      'do_out_n',    'do_out_c' ],
	      );


#####  Begin public methods 
#
#      note:  I'm not using accessor methods to get at most object
#             property variables.  On purpose.

=head1 METHODS

=over

=item my $piet = Piet::Interpreter->new( %args );

Instantiates and returns a new Piet::Interpreter object.  Valid
arguments are:

=over

=item image => 'my_prog.gif'

Specifies the program image file to load into the interpreter. 

=item codel_size => $size

Tells the interpreter how large a codel is, in pixels.  Defaults to 1.

=item nonstandard => ('white'|'black') 

Sets the behavior of non-standard colored codels to either 'white' or
'black'.  Defaults to 'white'.

=item debug => (1|0) 

Turns on debugging information, including warnings.

=item warn => (1|0) 

Turns on warnings only.

=item trace => (1|0) 

Turns on program tracing, which only outputs instructions and values.

=back

=cut

sub new {
    
    #  usage:  my $piet = Piet::Interpreter->new( debug => 1, ... );
    #
    #     The Instantiator.  Returns a new interpreter object, ready to go. 
    #     Accepts flags to initialize properties on creation.

    my ($class, %args) = @_;
    
    my $self = bless {

	_image       => undef,
	_filename    => undef,
	_rows        => undef,
	_cols        => undef,
	_matrix      => undef,
	_codel_size  => $args{codel_size}  || 1,
	_debug       => $args{debug}       || 0,
	_trace       => $args{trace}       || 0,
	_warn        => $args{warn}        || 0,
	_nonstandard => $args{nonstandard} || 'white', 

    }, ref($class) || $class;

    $self->reset;
    $self->image($args{image}) if $args{image};

    return $self;
}

=item $piet->reset;

Resets the PVM (Piet Virtual Machine) back to the default state.
After a reset, the current x and y should both be 0, the DP points to
the right, the CC points to the left, and the stack should be empty.

=cut

sub reset {

    #  usage:  $piet->reset;
    #
    #     Resets the PVM (Piet Virtual Machine) back to the initial state.

    my $self = shift;

    $self->{_dp}    =  0;   #   Direction Pointer:  0=right, 1=down, 2=left, 3=up
    $self->{_cc}    = -1;   #       Codel Chooser: -1=left, 1=right
    $self->{_cx}    =  0;   #  Current x position
    $self->{_cy}    =  0;   #  Current y position

    $self->{_stack}         = [];
    $self->{_change_flag}   = 0;
    $self->{_step_number}   = undef;
    $self->{_current_block} = undef;
    $self->{_block_value}   = undef;

    $self->{_last_color} = $self->matrix($self->{_cx},$self->{_cy});
}

=item $piet->image('myprog.gif');

Loads in a program image from the specified file.  The interpreter was
designed and tested using gif images, but any format that is supported
by Image::Magick should work just fine.  Once the file has been
loaded, it is inspected and processed, creating a run-matrix and
determining some useful properties from the image.  

Note: Be sure to set the codel size, if needed, before loading the
image.  Otherwise, a size of 1 will be assumed, and the codel columns
and rows will not be calculated correctly, causing pain and
irritation.

=cut

sub image {

    #  usage:  $piet->image('myprog.gif');
    #
    #     Loads in an image from a file to use as the Piet program.  Inspects
    #     the image, and generates properties and the run matrix from it.

    my ($self, $file) = @_;

    unless (defined $file) { 
	carp "No image file given in Piet::Interpreter::image()";
	return;
    }  
    unless (-e $file) {
	carp "File $file does not exist in Piet::Interpreter::image()";
	return;
    } 

    #  Read file into object and process

    $self->{_filename}  = $file;
    $self->{_image}     = Image::Magick->new;
    $self->{_image}->Read($file);

    $self->_process_image;
}

=item $piet->run;

Starts the Piet interpreter running from the upper-left codel.
Program execution is described under "Language Concepts", below.

=cut

sub run {

    #  usage:  $piet->run;
    #
    #     This is where the magic happens.  We initialize the PVM, and 
    #     start running through the program image.  

    my $self = shift; 
    return unless $self->{_matrix};

    $self->reset;
    print $self->to_text if $self->{_debug};

    #  starting at the upper left, start stepping through the codel blocks

    while (1) {
	$self->{_step_number} = $self->step;
	last unless $self->{_step_number};
    }

    $self->_debug("\nEnd Of Line.");
}

=item $done = $piet->step;

Performs one "step" of a Piet program, where a step is one transition
from one codel block to the next.  A failed transition (trying to go
out of bounds, or onto black) is not considered a step, but a slide
into or out of a while block is.  Returns the step count number, or
undef if the step terminates the program.

=cut

sub step {

    #  usage:  $done = $piet->step;
    #
    #     Performs one "step" of a Piet program, where a step is one transition
    #     from one codel block to the next.  A failed transition (trying to go
    #     out of bounds, or onto black) is not considered a step, but a slide
    #     into or out of a while block is.  Returns the step count number, or
    #     undef if the step terminates the program.

    my $self = shift;

    $self->_process_current_block;
    $self->{_step_number}++;
    $self->_debug("\n-- STEP:  $self->{_step_number}");

    my $tries_left = 8;

    while ($tries_left) {

	#  find the edge of the current codel color block in the
	#  direction of the dp, then find the codel on the edge
	#  furthest in the direction of the cc

	my ($ex, $ey) = $self->_get_edge_codel;
	
	#  get the codel immediately in the direction of the dp

	my ($nx, $ny) = $self->_get_next_codel($ex, $ey);
	
	if ( ! $self->_is_valid($nx,$ny) ) {
	    
	    #  pointer can't move; rotate dp or toggle cc and try again
	    
	    if ($self->{_change_flag}) {
		$self->{_dp} = ($self->{_dp} + 1) % 4;
		$self->{_change_flag} = 0;
	    }
	    else {
		$self->{_cc} = $self->{_cc} * -1;
		$self->{_change_flag} = 1;
	    }
	    
	    my $why = $self->_is_black($nx,$ny)?"black":"invalid";
	    $self->_debug(" trying again ($why at $nx,$ny) - new DP: ".
			  $self->{_dp}."  new CC: ".$self->{_cc});
	    
	    $tries_left--;
	    next;
	}

	elsif ( $self->_is_white($nx,$ny) ) {

	    #  slide across white squares - no operation performed

	    $self->_debug(" EX: $ex  EY: $ey  =>  NX: $nx  NY: $ny   (DP: ".
			  $self->{_dp}."  CC: ".$self->{_cc}.") (WHITE)");

	    $self->{_last_color} = $HEX_WHITE;
	}

	else {

	    #  get the color of the new codel, compare it with the color of
	    #  the last codel block, and look up the operation to perform

	    my $new_color = $self->matrix($nx,$ny);
	    $self->_debug(" EX: $ex  EY: $ey  =>  NX: $nx  NY: $ny   (DP: ".
			  $self->{_dp}."  CC: ".$self->{_cc}.")");
	    
	    $self->do_action($self->{_last_color}, 
			     $new_color, 
			     $self->{_block_value}) unless
				 ($self->{_last_color} eq $HEX_WHITE);
	    
	    $self->_debug("  STACK:  ".join(",",$self->_stack));
	    
	    $self->{_last_color} = $new_color;
	}

	#  set the new pixel and finish

	$self->{_cx} = $nx;
	$self->{_cy} = $ny;
	return $self->{_step_number};
    }
}


##  public accessor and output methods - no autoload! no Class::Struct! wooot!

=item $piet->debug(1);

Turns debugging information on or off.

=item $piet->warn(1);

Turns warnings on or off.

=item $piet->trace(1);

Turns program instruction tracing on or off.

=item $piet->codel_size(5);

Sets or returns the codel size for the program image.

=item $piet->nonstandard('white');

Sets the behavior of non-standard codels to 'white' or 'black'.

=item $rows = $piet->rows;

Returns the number of codel rows in the program image.

=item $cols = $piet->rows;

Returns the number of codel columns in the program image.

=item $file = $piet->rows;

Returns the name of the file from which the program image was loaded.

=cut

sub debug {
    my ($self, $val) = @_;
    $self->{_debug} = $val if (@_ > 1);
    return $self->{_debug};
}

sub warn {
    my ($self, $val) = @_;
    $self->{_warn} = $val if (@_ > 1);
    return $self->{_warn};
}

sub trace {
    my ($self, $val) = @_;
    $self->{_trace} = $val if (@_ > 1);
    return $self->{_trace};
}

sub codel_size {
    my ($self, $val) = @_;
    $self->{_codel_size} = $val if (@_ > 1);
    return $self->{_codel_size};
}

sub nonstandard {
    my ($self, $val) = @_;
    $self->{_nonstandard} = $val if (@_ > 1);
    return $self->{_nonstandard};
}

sub filename {
    my $self = shift;
    return $self->{_filename};
}

sub rows {
    my $self = shift;
    return $self->{_rows};
}

sub cols {
    my $self = shift;
    return $self->{_cols};
}


sub matrix {

    #  usage:  my $hex = $piet->matrix($x,$y);
    #          $piet->matrix($x,$y,'FF0000');
    #
    #     Allows the user to get or set the hex value for a given matrix cell.

    my ($self, $x, $y, $hex) = @_;

    if ($hex) {
	$self->{_matrix}[$x][$y] = $hex;
    }
    return $self->{_matrix}[$x][$y];
}

sub get_matrix {
    my $self = shift;
    return $self->{_matrix};
}

sub set_matrix {
    #   $matrix_ref should be a list of lists; see _process_image
    
    my ($self, $matrix_ref) = @_;
    $self->{_matrix} = $matrix_ref;
}

=item $piet->state("CHECK");

Prints detailed information about the state of the PVM, with an
optional label.  Information reported includes the filename, number of
codel columns and rows, which debugging, warning, or tracing flags are
set, how non-standard colored codels are handled, the step number, the
current x and y position of the pointer, the directions of the DP and
CC, the last color visited, and the values currently on the stack.

=cut

sub state {     

    ###  Prints detailed information about the PVM state, with a label
    
    my ($self, $label) = @_;
    
    print "$label:\n" if (defined $label);
    print "$self->{_filename}  ($self->{_cols} x $self->{_rows})   ";
    if ($self->{_warn}  || $self->{_debug} || 
	$self->{_trace} || $self->{_nonstandard}) {
	print "B" if ($self->{_nonstandard} eq 'black');
	print "D" if $self->{_debug};
	print "T" if $self->{_trace};
	print "W" if $self->{_warn};
    }
    print "\n";
    
    print "  Codel Size:  $self->{_codel_size}\n";
    print "  Step:  $self->{_step_number}   CX:  $self->{_cx}   CY:  $self->{_cy}" .
	  "   DP:  $self->{_dp}   CC:  $self->{_cc}\n";
    print "  Last color:  " . $hex2color{$self->{_last_color}} . "\n";
    print "  Stack:  " . join(",",$self->_stack) . "\n";
    
}

=item print $piet->to_text;

Returns a nicely formatted text version of the program image's codel
matrix, with the filename, codel size, and column/row information.

=back

=cut

sub to_text {

    ###  Prints a simple text representation of the program image to stdout

    my $self = shift;
    return unless $self->{_matrix};

    my $content = 
          "Image $self->{_filename}: ($self->{_cols} x $self->{_rows} ;" .
          " codel size $self->{_codel_size})\n";
    
    for my $j (0..($self->{_rows}-1)) {
	for my $i (0..($self->{_cols}-1)) {
	    my $hex = $self->matrix($i, $j);
	    $content .= "$hex2abbr{$hex} ";
	}
	$content .= "\n";
    }

    return $content;
}


#####  Piet function subroutines
#      (leaving these "public" for now, for testing purposes)

sub do_action {

    ###  takes old and new hex colors, plus a block value, and performs
    ###  the appropriate operation

    my ($self, $old, $new, $value) = @_;

    $self->_debug("  Old Color: $hex2color{$old} => New Color: $hex2color{$new}");
    my $diff_hue   = ($hex2hue{$new}   - $hex2hue{$old})   % 6;
    my $diff_light = ($hex2light{$new} - $hex2light{$old}) % 3;

    my $method = $do_arr[$diff_hue][$diff_light];
    $self->$method($value);
}

sub do_noop {

    ###  does nothing.  should never be called, included for completeness

    my $self = shift;

    $self->_debug(" OPER: noop");
    $self->_trace("NOOP");
}

sub do_push {

    ###  pushes the given block value onto the stack

    my ($self, $block_value) = @_;

    $self->_debug(" OPER: push ($block_value)");
    $self->_trace("PUSH $block_value");

    $self->_stack_push($block_value);
}

sub do_pop {

    ###  pops the top value from the stack and discards it

    my $self = shift;

    my $tmp = $self->_stack_pop;
    defined($tmp) or return;

    $self->_debug(" OPER: pop ($tmp)");
    $self->_trace("POP  $tmp");
}

sub do_add {

    ###  Pops the top two values off the stack, adds them, and pushes
    ###  the result back on the stack.

    my $self = shift;

    my $top  = $self->_stack_pop;
    my $next = $self->_stack_pop;
    $self->_stack_push($next+$top);

    $self->_debug(" OPER: add     ".($next+$top));
    $self->_trace("ADD  $next $top");
}

sub do_subtract {

    ###  Pops the top two values off the stack, subtracts the top value 
    ###  from the second top value, and pushes the result back on the stack.

    my $self = shift;

    my $top  = $self->_stack_pop;
    my $next = $self->_stack_pop;
    defined($top) or return;
    defined($next) or return;
    $self->_stack_push($next-$top);

    $self->_debug(" OPER: subtract    ".($next-$top));
    $self->_trace("SUB  $next $top");
}

sub do_multiply {

    ###  Pops the top two values off the stack, multiplies them, and
    ###  pushes the result back on the stack.

    my $self = shift;

    my $top  = $self->_stack_pop;
    my $next = $self->_stack_pop;
    defined($top) or return;
    defined($next) or return;
    $self->_stack_push($next*$top);

    $self->_debug(" OPER: multiply    ".($next*$top));
    $self->_trace("MULT $next $top");
}

sub do_divide {

    ###  Pops the top two values off the stack, calculates the integer
    ###  division of the second top value by the top value, and pushes
    ###  the result back on the stack.

    my $self = shift;

    my $top  = $self->_stack_pop;
    my $next = $self->_stack_pop;
    defined($top) or return;
    defined($next) or return;
    $self->_stack_push(int($next/$top));

    $self->_debug(" OPER: divide    ".(int($next/$top)));
    $self->_trace("DIV  $next $top");
}

sub do_mod {

    ###  Pops the top two values off the stack, calculates the second top 
    ###  value modulo the top value, and pushes the result back on the stack.

    my $self = shift;

    my $top  = $self->_stack_pop;
    my $next = $self->_stack_pop;
    $self->_stack_push($next%$top);

    $self->_debug(" OPER: mod     ".($next%$top));
    $self->_trace("MOD  $next $top");
}

sub do_not {

    ###  Replaces the top value of the stack with 0 if it is non-zero,
    ###  or 1 if it is zero.

    my $self = shift;

    my $top = $self->_stack_pop;
    defined($top) or return;
    $self->_stack_push(!$top+0);

    $self->_debug(" OPER: not    ".(!$top+0));
    $self->_trace("NOT  $top");
}

sub do_greater {

    ###  Pops the top two values off the stack, and pushes 1 on to the
    ###  stack if the second top value is greater than the top value,
    ###  or 0 if it is not greater.

    my $self = shift;

    my $top  = $self->_stack_pop;
    my $next = $self->_stack_pop;
    $self->_stack_push((($next>$top)?1:0)+0);

    $self->_debug(" OPER: greater   ".((($next>$top)?1:0)+0));
    $self->_trace("GTR  $next $top");
}

sub do_pointer {

    ###  Pops the top value off the stack and rotates the DP clockwise
    ###  that many steps, or counterclockwise if it is negative.

    my $self = shift;

    my $top = $self->_stack_pop;

    $self->_debug(" OPER: pointer  ($top)");
    $self->_trace("PNTR $top");

    $self->{_dp} = ($self->{_dp} + $top) % 4;
}

sub do_switch {

    ###  Pops the top value off the stack and toggles the CC that many times. 

    my $self = shift;

    my $top = $self->_stack_pop;
    defined($top) or return;

    $self->_debug(" OPER: switch   ($top)");
    $self->_trace("SWCH $top");

    $self->{_cc} = $self->{_cc} * -1 if ($top %2);
}

sub do_duplicate {

    ###  Pushes a copy of the top value on the stack on to the stack. 

    my $self = shift;

    my $top = $self->_stack_pop;
    defined($top) or return;
    $self->_stack_push($top);
    $self->_stack_push($top);

    $self->_debug(" OPER: duplicate  ($top)");
    $self->_trace("DUP  $top");
}

sub do_roll {

    ###  Pops the top two values off the stack and "rolls" the
    ###  remaining stack entries to a depth equal to the second value
    ###  popped, by a number of rolls equal to the first value
    ###  popped. A single roll to depth n is defined as burying the
    ###  top value on the stack n deep and bringing all values above
    ###  it up by 1 place. A negative number of rolls rolls in the
    ###  opposite direction. A negative depth is an error and the
    ###  command is ignored.

    my $self = shift;

    # there's always got to be one bad apple in the bunch...

    my $num   = $self->_stack_pop;
    my $depth = $self->_stack_pop;
    defined($num) or return;
    defined($depth) or return;

    $self->_debug(" OPER: roll:  $num times, $depth deep");
    $self->_trace("ROLL $depth $num");

    $num = $num % $depth;
    return if ($depth <= 0);
    return if ($num   == 0);

    my @stack = $self->_stack;
    my @tmp = @stack[($#stack-$depth+1)..$#stack]; 

    if ($num>0) {
	@tmp = (@tmp[-$num..-1], @tmp[0..($#tmp-$num)]); 
    }
    else {
	@tmp = (@tmp[-$num..$#tmp], @tmp[0..(-$num-1)]); 
    }

    splice(@stack, $#stack-$depth+1, $depth, @tmp);
    $self->{_stack} = \@stack;
}

sub do_in_n {

    ###  Reads a value from STDIN as a number, and pushes it on to the stack.

    my $self = shift;

    my $c = &_getone;

    $self->_debug(" OPER: in_n:  got $c");
    $self->_trace("N_IN");

    $self->_stack_push($c);
}

sub do_out_n {

    ###  Pops the top value off the stack and prints it to STDOUT as a number.

    my $self = shift;

    my $top = $self->_stack_pop;
    defined($top) or return;
    print $top unless $self->{_trace};

    $self->_debug(" OPER: out_n      OUT - $top");
    $self->_trace("NOUT $top");
}

sub do_in_c {

    ###  Reads a value from STDIN as a character, and pushes it on to the stack.

    my $self = shift;

    my $c = ord(&_getone);         #  should this be:  my $c = <>; chomp $c;   ?  

    $self->_debug(" OPER: in_c:  got $c");
    $self->_trace("C_IN");

    $self->_stack_push($c);
}

sub do_out_c {

    ###  Pops the top value off the stack and prints it to STDOUT as a character.

    my $self = shift;

    my $top = $self->_stack_pop;
    defined($top) or return;
    $top = chr($top);
    print $top unless $self->{_trace};

    $self->_debug(" OPER: out_c       OUT - $top");
    $self->_trace("COUT $top");
}


#####  begin "private" methods


sub _rgba2hex {

    ###  converts ImageMagick's RGBA format to a friendlier hex number
    #       bug?  we have to divide by 257 to get the right range - is this right?

    my ($number, $hex);
    (shift @_) =~ /^(\d+),(\d+),(\d+)/;
    for $number ($1,$2,$3) {
	$hex .= sprintf("%02X", $number/257);
    }
    return $hex;
}


sub _process_image {
    
    ###  generates useful information and the run matrix from the image property

    my $self = shift;
    my @matrix;

    return unless (my $img = $self->{_image});

    $self->{_cols}   = $img->Get('columns');
    $self->{_rows}   = $img->Get('rows');

    #  cycle through image and populate run matrix
    #  note:  only reads every $codel_size pixels, skips over the rest

    my $j = 0;
    while ($j <= ($self->{_rows}-1)) {
	my $i = 0;
	while ($i <= ($self->{_cols}-1)) {
	    $matrix[int($i/$self->{_codel_size})][int($j/$self->{_codel_size})] =
		_rgba2hex($self->{_image}->Get("pixel[$i,$j]"));
	    $i += $self->{_codel_size};
	}
	$j += $self->{_codel_size};
    }

    $self->{_matrix} = \@matrix;
    $self->{_cols} /= $self->{_codel_size};
    $self->{_rows} /= $self->{_codel_size};
}


sub _process_current_block {

    ###  processes and retrieves information about current codel block.
    ###  a color block is an array of [$x,$y] coordinate pairs.
    #
    #       todo:  color block memoization

    my $self = shift;
    
    $self->{_codels_seen} = { "$self->{_cx}\_$self->{_cy}" => 1 };

    my @codel_list = $self->_neighbor_list( $self->{_cx}, $self->{_cy} );

    $self->{_current_block} = \@codel_list;
    $self->{_block_value}   = scalar @codel_list;
    $self->{_codels_seen}   = undef;
}


sub _neighbor_list {
    
    ###  sister method to _process_current_block, calls itself recursively
    ###  to generate a list of seed-filled neighbor codels

    my @result;
    my @stack;
    my ($self, $x, $y) = @_;
    $self->{_codels_seen}{"$x\_$y"} = 1;
    push @stack, [$x, $y];
    while( $#stack > -1 )
    {
    ($x, $y) = @{ pop @stack };
    push @result, [$x, $y];
    
    my $hex  = $self->matrix($x,$y);
    
    #  loop through the codels above, below, left, and right of the current one
 
    for my $i (-1, 0, 1) {
	for my $j (-1, 0, 1) {
	    next if (abs($i)==abs($j));

	    my $m=$x+$i;
	    my $n=$y+$j;

	    #  if the selected adjacent codel is in range, not black, and the 
	    #  same color as the current codel, then howdy, neighbor!

	    next unless $self->_is_valid($m,$n);
	    
	    if ((!defined $self->{_codels_seen}{"$m\_$n"}) &&
		($self->matrix($m, $n) eq $hex)) {
		push (@stack, [$m,$n]);
	    }
	    $self->{_codels_seen}{"$m\_$n"} = 1;
	}
    }

    }

    return @result;
}


sub _is_valid {

    ###  returns false if codel is out of bounds or black, true otherwise

    my ($self, $x, $y) = @_;
    return !(($x >= $self->{_cols}) || ($x < 0) ||
	     ($y >= $self->{_rows}) || ($y < 0) ||
	     ($self->_is_black($x,$y)));
}


sub _is_black {

    ###  returns true if codel is "black", false otherwise

    my ($self, $x, $y) = @_;
    return unless (my $hex = $self->matrix($x, $y));

    return ($self->{_nonstandard} eq 'black') &&
           (!defined $hex2color{$hex})        ||
           ($hex eq $HEX_BLACK);
}


sub _is_white {

    ###  returns true if codel is "white", false otherwise

    my ($self, $x, $y) = @_;
    my $hex = $self->matrix($x, $y);

    return ($self->{_nonstandard} eq 'white') &&
           (!defined $hex2color{$hex}) || 
           ($hex eq $HEX_WHITE);
}


sub _get_next_codel {
    
    ###  finds the edge of the current codel block, and returns a
    ###  point in the direction of the dp from it

    my ($self, $x, $y) = @_;
    
    if    ($self->{_dp} == 1) { $y++ }
    elsif ($self->{_dp} == 2) { $x-- }
    elsif ($self->{_dp} == 3) { $y-- }
    else                      { $x++ }
    
    return ($x, $y);
}


sub _get_edge_codel {

    ###  returns the codel point on the far edge of the current block.
    ###  gets the edge by finding the index furthest in the direction
    ###  of the dp, then getting all points with that index.

    my $self = shift;
    my $codel;

    #    I know it looks like dark magic, but it's really just a bunch 
    #    of brain dead point sorting stuff all mushed together.

    if    ($self->{_dp} == 1) {
	my @sorted = sort {$$b[1] <=> $$a[1]} @{$self->{_current_block}};
	my @edge   = sort {$$a[0] <=> $$b[0]} grep {$$_[1] == $sorted[0][1]} @sorted;
	$codel     = ($self->{_cc}>0)?$edge[0]:$edge[$#edge];
    }
    elsif ($self->{_dp} == 2) {
	my @sorted = sort {$$a[0] <=> $$b[0]} @{$self->{_current_block}};
	my @edge   = sort {$$a[1] <=> $$b[1]} grep {$$_[0] == $sorted[0][0]} @sorted;
	$codel     = ($self->{_cc}>0)?$edge[0]:$edge[$#edge];
    }
    elsif ($self->{_dp} == 3) {
	my @sorted = sort {$$a[1] <=> $$b[1]} @{$self->{_current_block}};
	my @edge   = sort {$$a[0] <=> $$b[0]} grep {$$_[1] == $sorted[0][1]} @sorted;
	$codel     = ($self->{_cc}>0)?$edge[$#edge]:$edge[0];
    }
    else {
	my @sorted = sort {$$b[0] <=> $$a[0]} @{$self->{_current_block}};
	my @edge   = sort {$$a[1] <=> $$b[1]} grep {$$_[0] == $sorted[0][0]} @sorted;
	$codel     = ($self->{_cc}>0)?$edge[$#edge]:$edge[0];
    }

    return @$codel;
}

sub _stack {
    my $self = shift;
    return @{$self->{_stack}};
}

sub _stack_push {
    my ($self, $value) = @_;
    push(@{$self->{_stack}},$value);
}

sub _stack_pop {
    my $self = shift;
    return pop @{$self->{_stack}};
}


#  I'm going to assume that Term::ReadKey isn't installed, and do some magic here.

BEGIN { use POSIX qw(:termios_h);
        my ($term, $oterm, $echo, $noecho, $fd_stdin);
        $fd_stdin = fileno(STDIN);
        $term     = POSIX::Termios->new();
        $term->getattr($fd_stdin);
        $oterm    = $term->getlflag();
        $echo     = ECHO | ECHOK | ICANON;
        $noecho   = $oterm & ~$echo;
	
	sub _getone () {
	    my $key = '';
	    $term->setlflag($oterm);
	    $term->setcc(VTIME, 0);
	    $term->setattr($fd_stdin, TCSANOW);
	    sysread(STDIN, $key, 1);
	    return $key;
	}
}


#  These little guys look identical, but are really used for two different things.  Really.

sub _debug {
    my $self = shift;
    if ($self->{_debug}) {
        my $message = shift;
	print "$message\n";
    }
}

sub _trace {
    my $self = shift;
    if ($self->{_trace}) {
	my $message = shift ;
	print "  $message\n";
    }
}


=head1 LANGUAGE CONCEPTS

=head2 Colors

=begin text

 #FFC0C0    #FFFFC0      #C0FFC0    #C0FFFF    #C0C0FF      #FFC0FF
light red light yellow light green light cyan light blue light magenta

 #FF0000    #FFFF00      #00FF00    #00FFFF    #0000FF      #FF00FF
   red       yellow       green       cyan       blue       magenta

 #C00000    #C0C000      #00C000    #00C0C0    #0000C0      #C000C0
dark red  dark yellow  dark green  dark cyan  dark blue   dark magenta

                 #FFFFFF                  #000000
                  white                    black 

=end text

Piet uses 20 distinct colors, 18 of which are related cyclically in two ways:

=head3 Hue Cycle:

Red -> Yellow -> Cyan -> Blue -> Magenta -> Red

=head3 Lightness Cycle:

Light -> Normal -> Dark -> Light

Note that "light" is considered to be one step "darker" than "dark",
and vice versa.  White and black do not fall into either cycle.

Additional colors (such as orange or brown) may also be used.  In the
default case, non-standard colors are treated by the PVM (Piet Virtual
Machine) as the same as white, so may be used freely wherever white is
used.  You may also use the nonstandard() method to tell the PVM to
treat them the same as black.

=head2 Codels

Piet code takes the form of an image made up of the recognised colors.
Individual pixels of color are significant in the language, so it is
common for programs to be enlarged for viewing so that the details are
easily visible.  In such enlarged programs, the term "codel" is used
to mean a block of color equivalent to a single pixel of code, to
avoid confusion with the actual pixels of the enlarged graphic, of
which many may make up one codel.

=head2 Stack

Piet uses a stack for storage of all data values.  Data values exist
only as integers, though they may be read in or printed as Unicode
character values with the appropriate commands.

=head2 Program Execution

The Piet language interpreter begins executing a program in the color
block which includes the upper left codel of the program.  The
interpreter maintains a Direction Pointer (DP), initially pointing to
the right.  The DP may point either right, left, down or up.  The
interpreter also maintains a Codel Chooser (CC), initially pointing
left. The CC may point either left or right.  The directions of the DP
and CC will often change during program execution.  As it executes the
program, the interpreter traverses the color blocks of the program
under the following rules:

=over

=item 1 

The interpreter finds the edge of the current color block which is
furthest in the direction of the DP. (This edge may be disjoint if the
block is of a complex shape.)

=item 2

The interpreter finds the codel of the current color block on that
edge which is furthest to the CC's direction of the DP's direction of
travel.  (For example, if the DP points downwards, and the CC is to
the left, the interpreter looks for the rightmost codel on the edge.)

=item 3

The interpreter travels from that codel into the color block
containing the codel immediately in the direction of the DP.  

=back

The interpreter continues doing this until the program terminates.

=head1 SYNTAX ELEMENTS

=head2 Numbers

Each non-black, non-white color block in a Piet program represents an
integer equal to the number of codels in that block.  Note that
non-positive integers cannot be represented, although they can be
constructed with operators.  When the interpreter encounters a number,
it does not necessarily do anything with it.  In particular, it is not
automatically pushed on to the stack - there is an explicit command
for that.

=head2 Black Blocks and Edges

Black color blocks and the edges of the program restrict program flow.
If the Piet interpreter attempts to move into a black block or off an
edge, it is stopped and the CC is toggled.  The interpreter then
attempts to move from its current block again.  If it fails a second
time, the DP is moved clockwise one step.  These attempts are
repeated, with the CC and DP being changed between alternate attempts.
If, after eight attempts the interpreter cannot leave its current
color block, there is no way out and the program terminates.

=head2 White Blocks

White color blocks are "free" zones through which the interpreter
passes unhindered.  If it moves from a color block into a white area,
the interpreter "slides" through the white codels in the direction of
the DP until it reaches a non-white color block.  If the interpreter
slides into a black block or an edge, it is considered restricted (see
above), otherwise it moves into the color block so encountered.
Sliding across white blocks does not cause a command to be executed.

=head2 Commands

Commands are defined by the transition of color from one color block
to the next as the interpreter travels through the program.  The
number of steps along the Hue Cycle and Lightness Cycle in each
transition determine the command executed, as shown in the table
below.  If the transition between color blocks occurs via a slide
across a white block, no command is executed.

=over

=item (0 hue steps, 1 step darker) => B<push>

Pushes the value of the color block just exited on to the stack.
Note: values are not automatically pushed onto the stack - the push
operation must be explicitly carried out.

=item (0 hue steps, 2 steps darker) => B<pop>

Pops the top value off the stack and discards it. 

=item (1 hue step, 0 steps darker) => B<add>

Pops the top two values off the stack, adds them, and pushes the
result back on the stack.

=item (1 hue step, 1 step darker) => B<subtract>

Pops the top two values off the stack, subtracts the top value from
the second top value, and pushes the result back on the stack. 

=item (1 hue step, 2 steps darker) => B<multiply>

Pops the top two values off the stack, multiplies them, and pushes the
result back on the stack. 

=item (2 hue steps, 0 steps darker) => B<divide>

Pops the top two values off the stack, calculates the integer division
of the second top value by the top value, and pushes the result back
on the stack. 

=item (2 hue steps, 1 step darker) => B<mod>

Pops the top two values off the stack, calculates the second top value
modulo the top value, and pushes the result back on the stack. 

=item (2 hue steps, 2 steps darker) => B<not>

Replaces the top value of the stack with 0 if it is non-zero, and 1 if
it is zero. 

=item (3 hue steps, 0 steps darker) => B<greater>

Pops the top two values off the stack, and pushes 1 on to the stack if
the second top value is greater than the top value, and pushes 0 if it
is not greater. 

=item (3 hue steps, 1 step darker) => B<pointer>

Pops the top value off the stack and rotates the DP clockwise that
many steps, or counterclockwise if it is negative. 

=item (3 hue steps, 2 steps darker) => B<switch>

Pops the top value off the stack and toggles the CC that many times. 

=item (4 hue steps, 0 steps darker) => B<duplicate>

Pushes a copy of the top value on the stack on to the stack. 

=item (4 hue steps, 1 step darker) => B<roll>

Pops the top two values off the stack and "rolls" the remaining stack
entries to a depth equal to the second value popped, by a number of
rolls equal to the first value popped. A single roll to depth nis
defined as burying the top value on the stack n deep and bringing all
values above it up by 1 place. A negative number of rolls rolls in the
opposite direction. A negative depth is an error and the command is
ignored. 

=item (4 hue steps, 2 steps darker) => B<number_in>

Reads a character from STDIN as a number, and pushes it on to the stack.

=item (5 hue steps, 0 steps darker) => B<character_in>

Reads a value from STDIN as a character, and pushes it on to the stack.

=item (5 hue steps, 1 step darker) => B<number_out>

Pops the top value off the stack and prints it to STDOUT as a number.

=item (5 hue steps, 2 steps darker) => B<character_out>

Reads a value from STDIN as a character, and pushes it on to the stack.

=back

Any operations which cannot be performed (such as popping values when
not enough are on the stack) are simply ignored.

=head1 AUTHOR

Marc Majcher (piet-interpreter@majcher.com)

=head1 SEE ALSO

L<http://www.majcher.com/code/piet> 

L<http://www.physics.usyd.edu.au/~mar/esoteric/piet.html>

=cut


1;

