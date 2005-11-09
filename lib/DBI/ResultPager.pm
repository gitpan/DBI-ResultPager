#!/usr/bin/perl

package DBI::ResultPager;

use strict;
use warnings;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use DBI;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA);
	$VERSION = '0.9.0';
	@ISA = qw(Exporter);
}


sub new {
	my $self = {};
	$self->{DBH} = '';
	$self->{QUERY} = '';
	$self->{PERPAGE} = 100;
	$self->{DEFAULTORDER} = '';

	my %fmt = ();
	my %hidden = ();
	my @cc;
	
	$self->{FORMATTERS} = \%fmt;
	$self->{CUSTOMCOLUMNS} = \@cc;
	$self->{HIDDENCOLUMNS} = \%hidden;
	
	bless($self);
	return $self;	
}

sub display {
	my $self = shift;
	my @columns;
	my $page = 1;
	
	if(defined(url_param('page'))) {
		$page = url_param('page');
	}

	my $hidden = $self->{HIDDENCOLUMNS};
	my $query = $self->{QUERY};
	my $perpage = $self->{PERPAGE};
	my $offset = (($page - 1) * $perpage);
	my $dbh = $self->{DBH};
	my $order = $self->{DEFAULTORDER};
	
	my $ccref = $self->{CUSTOMCOLUMNS};
	my @customColumns = @$ccref;
	
	if($order ne '') {
		$query = $query . ' order by ' . $order;
	}

	$query = $query . ' limit ' . ($perpage + 1);

	if($page ne 1) {
		$query = $query . " offset $offset";
	}

	#print "$query<br />";
		
	my $sth = $dbh->prepare($query);
	$sth->execute or die "Error in $query: $!\n";

	print '<center><table width="90%" border="0">';
	
	my $nref = $sth->{NAME};
	my @names = @$nref;

	# Print the header.
	print '<tr>';
	foreach(@names) {
		if(!defined($hidden->{$_})) {
			print '<th>' . $_ . '</th>';
		}
		
		push(@columns, $_);		
	}

	foreach(@customColumns) {
		print '<th>' . $_->{'columnName'} . '</th>';
	}

	# Add headers for any custom columns
	
	print '</tr>';
	
	my $formatters = $self->{FORMATTERS};
	my $count = 0;
	while(my @row = $sth->fetchrow_array()) {
		$count++;
		
		if($count > $perpage) { next; }

		my $color = "";
		if( ($count %2) eq 1) {
			$color = ' bgcolor="#EEEEEE"';
		}

		print "<tr$color>";
		my $colcount = 0;

		foreach(@row) {
			$colcount++;
			my $colname = $columns[$colcount - 1];
			
			if(defined($hidden->{$colname})) { next; }
			
			print '<td>';

			# Check if this column has a custom formatter
			if(defined($formatters->{$colname})) {
				my $subref = $formatters->{$colname};
				print &$subref($_);
			} else {	
				print $_;
			}

			print '</td>';
		}
	
		foreach(@customColumns) {
			print '<td>';
			my $cref = $_->{'codeRef'};
			print &$cref(@row);
			print '</td>';
		}

		print '</tr>';
	}

	print '</table>';

	if($count > $perpage) {
		my $u = url(-relative=>1, -query=>1);
		if($u =~ /[\?&;]page=/) {
			$u =~ s/[\?&;]page=[0-9]*//;
		}

		if($u =~ /\?/) {
			$u = $u . '&page=' . ($page + 1);
		} else {
			$u = $u . '?page=' . ($page + 1);
		}
		
		print '<a href="'. $u . '">Next Page</a>';
	}
	
	print '</center>';
}

sub hideColumn {
	my ($self, $columnName) = (@_);
	my $ar = $self->{HIDDENCOLUMNS};
	$ar->{$columnName} = 1;
}

sub addCustomColumn {
	my ($self, $columnName, $codeRef, $identityColumn) = (@_);

	my %cc = ();
	
	$cc{'columnName'} = $columnName;
	$cc{'codeRef'} = $codeRef;
	
	my $ar = $self->{CUSTOMCOLUMNS};
	push(@$ar, \%cc); # Push the hashref onto the arrayref.
}

sub addColumnFormatter {
	my ($self, $column, $formatref) = (@_);

	my $formatters = $self->{FORMATTERS};
	$formatters->{$column} = $formatref;
}

sub defaultorder {
	my $self = shift;
	if(@_) { $self->{DEFAULTORDER} = shift; }
	return $self->{DEFAULTORDER};
}

sub dbh {
	my $self = shift;
	if(@_) { $self->{DBH} = shift; }
	return $self->{DBH};
}

sub query {
	my $self = shift;
	if(@_) { $self->{QUERY} = shift; }
	return $self->{QUERY};
}

1;
__END__

=head1 NAME

DBI::ResultPager - creates an HTML-based pager for DBI result sets.

=head1 SYNOPSIS

 # Create a pageable result set
 my $rp = DBI::ResultPager->new;
 $rp->dbh($dbh);
 $rp->query('select books.title, authors.name
             from books
	     inner join (books.author_id = authors.id)');
 $rp->display();

 # The same result set, but sorted with nicer column headings
 my $rp = DBI::ResultPager->new;
 $rp->dbh($dbh);
 $rp->query('select books.title as "Title", 
             authors.name as "Author"
             from books
	     inner join (books.author_id = authors.id)');
 $rp->defaultOrder('Title');
 $rp->display();

 # Adding a custom formatter to build links
 my $rp = DBI::ResultPager->new;
 $rp->dbh($dbh);
 $rp->query('select books.title as "Title", 
             books.isbn as "ISBN",
             authors.name as "Author"
             from books
	     inner join (books.author_id = authors.id)');
 $rp->addColumnFormatter('ISBN', \&linkISBN);
 $rp->display();

 sub linkISBN {
     my($isbn) = shift;
     return '<a href="http://isbndb.com/search-all.html?kw=' .
         $isbn . '">ISBNdb</a>';
 }

 # Adding a custom column and hiding an identity column
 my $rp = DBI::ResultPager->new;
 $rp->dbh($dbh);
 $rp->query('select books.id,
             books.title as "Title", 
             from books');
 $rp->hideColumn('books.id');
 $rp->addCustomColumn('Functions', \&bookFunctions);
 $rp->display();
 
 sub bookFunctions {
   my (@row) = (@_);
   return '<a href="delete.cgi?id=' . $row[0] . '">delete</a>';
 }
 

=head1 DESCRIPTION

This class is a quick and easy method of paging result sets returned 
from the DBI database interface.  It takes a standard SQL query along 
with a database handle and performs the query, inserting the resultant 
rows into a pageable HTML table.  Various options such as sort order can 
be adjusted, and columns can have formatters attached.  Columns can also 
be hidden, and custom columns can be added to the output.

=head1 METHODS

=head1 SOURCE AVAILABILITY

The source for this project should always be available from CPAN.  Other than
that it may be found at http://www.neuro-tech.net/.

=head1 AUTHOR

	Original code:		Luke Reeves <luke@neuro-tech.net>
				http://www.neuro-tech.net/

=head1 COPYRIGHT

Copyright (c) 2005 Luke Reeves <luke@neuro-tech.net>

DBI::ResultPager is free software. You can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 CREDITS

 Luke Reeves <luke@neuro-tech.net>

=head1 SEE ALSO

perl(1), DBI(3).

=cut

