
# allows download of large VCF files
# input files should be bgziped and indexed with tabix
# also requires a file with list of chromosomes

use strict;
use warnings;

my $cgi = new CGI;

my $start = $cgi->param('start');
if (!$start) {
    $start = 0;
}
my $stop = $cgi->param('stop');
if (!$stop) {
    $stop = 0;
}
my $min = "";
my $max = "";

my $function = $cgi->param('function');
if (!$function) {
    use CXGN::Page;
    use CXGN::Page::FormattingHelpers qw/ page_title_html info_section_html /;
    my $page = CXGN::Page->new("VCF Download");
    my $title = page_title_html("VCF Download");
    $page->header("Downloads", $title);
    $page->jsan_use("download-vcf");

print "<h2>Download Genotype Data</h2>\n";
print "This tool allows you to quickly download a portion of a genotype experiment.<br>\n";
print "Select a genotype experiment, chromosome, and range.<br>\n";
print "The output format is Variant Call Format (VCF) and can be viewed in TASSEL (File => Open) or Excel (File => Open, Tab Delimeted).<br><br>\n";

my $option1 = "1kEC_genotype01222019";
my $option2 = "1kEC_genotype01222019f";
my $option3 = "all_filtered_snps_allaccessions_allploidy_snpeff";
my $option4 = "2019_hapmap";
my $option5 = "watkins-filtered-cleaned";

print "<table>";
print "<tr><td>Genotype trial:<td><select id=trial onchange=\"getChromFile()\">";
print "<option value=$option1>Exome Capture 2019 Diversity</option>\n";
print "<option value=$option2>Exome Capture 2019 Diversity filtered</option>\n";
print "<option value=$option3>Exome Capture 2017 WheatCAP_UCD</option>\n";
print "<option value=$option4>Exome Capture 2019 HapMap</option>";
print "<option value=$option5>Exome Capture Watkins</option>";

print "</select>\n";
print "<tr><td>Chromosome:<td><div id=\"step1\"><select id=chrom>";
print "<option>select</option>";
my $file_chr = "/home/production/genotype_files/1kEC_genotype01222019.txt";
open(IN, $file_chr);
while (<IN>) {
    chomp;
    print "<option value=$_>$_</option>\n";
}
close(IN);
print "</select></div>";
print "<tr><td>Start:<td><input type=\"text\" id=\"start\" value=\"$start\"><td>$min\n";
print "<tr><td>Stop:<td><input type=\"text\" id=\"stop\" value=\"$stop\"><td>$max\n";
print "<tr><td><input type=\"button\" value=\"Query\" onclick=\"select_chrom()\"/>";

print "</table>\n";

print "<div id=\"step2\"></div>";

} elsif ($function eq "valid") {
    print "content-type: text/csv \n\n";
    print "Id,Trial\n";
    print "87,SeqCap_KSU_tabix\n";
    print "8123,2019_hapmap\n";
    print "8124,1kEC_genotype01222019\n";
    print "8125,2017_WheatCAP\n";
} elsif ($function eq "download") {
    my $filename = $cgi->param('filename');
    my $trial = $cgi->param('trial') . ".tsv";
    open(IN, $filename) or print STDERR "Error: $filename not found\n";;
    print "Content-type: application/vnd.ms-excel\n";
    print "Content-Disposition: attachment; filename=\"$filename\"\n";
    while (<IN>) {
	print "$_";
    }
    close(IN);
} elsif ($function eq "readChrom") {
    my $file_chr = "/home/production/genotype_files/" . $cgi->param('trial') . ".txt";
    open(IN, $file_chr) or print STDERR  "Error: $file_chr not found\n";
    print "<select id=chrom>";
    while (<IN>) {
        chomp;
        print "<option value=$_>$_</option>\n";
    }
    close(IN);
    print "</select>";
} else {
    my $trial = $cgi->param('trial'); 
    my $chrom = $cgi->param('chrom');
    my $file = "/home/production/genotype_files/" . $trial . ".vcf.gz";
    my $file_pas = "/home/production/genotype_files/" . $cgi->param('trial') . ".passport.xls";
    my $unique_str = int(rand(10000000));
    my $dir = "/home/production/tmp/triticum-site/download/download_" . $unique_str;
    if ( !-d "/home/production/tmp/triticum-site/download") {
	mkdir "/home/production/tmp/tritticum-site/download";
    }
    if ($chrom =~ /([a-z]*[A-Z0-9]+)/) {
        $chrom = $1;
    } else {
        print "Select a chromosome";
        die;
    }
    unless(mkdir $dir) {
        die "Unable to create $dir\n";
    }
    my $filename1 = $dir . "/" . $trial . ".vcf";
    my $filename2 = $dir . "/proc_error.txt";
    my $filename3 = $trial . ".vcf";
    my $filename4 = $dir . "/" . $trial . ".tsv";

    my $cmd = "tabix -h $file $chrom:$start-$stop > $filename1 2> $filename2";
    #print "$cmd<br>\n";
    system($cmd);

    my $count = 0;
    my @line;
    my $geno;
    my $chr;
    my $ref;
    my $alt;
    my $a1;
    my $a2;
    my $errorLog = "";
    if (-e $filename2) {
        open(IN, $filename2);
        while (<IN>) {
            $errorLog .= $_;
        }
        close(IN);
    }
    if (-e $filename1) {
	open(IN, $filename1);
	open(OUT, '>', $filename4);
	print OUT "rs#\talleles\tchrom\tpos";
        while (<IN>) {
	    if (/#CHROM/) {
		@line = split('\t', $_);
		foreach my $key (keys @line) {
		    if ($key > 8) {
			print OUT "\t$line[$key]";
		    }
		}
	    } elsif (!/^#/) {
                $count++;
		@line = split('\t', $_);
		$chr = $line[0];
		$ref = $line[3];
		$alt = $line[4];
		foreach my $key (keys @line) {
		    if ($key == 1) {
			print OUT "$line[2]\t$ref$alt\t$chr\t$line[1]";
		    } elsif ($key > 8) {
			$geno = $line[$key];
			$a1 = substr($geno,0,1);
			$a2 = substr($geno,2,1);
			if ($a1 eq "0") {
			    print OUT "\t$ref";
			} elsif ($a1 eq "1") {
			    print OUT "\t$alt";
			} elsif ($a eq ".") {
			    print OUT "\tN";
			} else {
			    print OUT "\t?";
			}
		    }
		}
		print OUT "\n";
            }
        }
        close(IN);
	close(OUT);
    }
    if (($errorLog ne "") && ($count != 0)) {
        print "Content-type: text/plain\n";
        print "Content-Disposition: attachment; filename=\"$trial\"\n";
        print "$errorLog\n";
    } elsif ($function eq "queryDownload") {
        print "Content-type: application/vnd.ms-excel\n";
        print "Content-Disposition: attachment; filename=\"$filename3\"\n";
        if (-e $filename1) {
            open(IN, $filename1);
            while (<IN>) {
              print "$_";
            }
        }
        close(IN);
    } else {
      if ($count > 0) {
          #print "<input type=\"button\" value=\"Download $count markers from $chrom:$start-$stop\" onclick=\"javascript:window.open('$filename1')\">";
          print "<br><input type=\"button\" value=\"Download $count markers from $chrom:$start-$stop\" onclick=\"javascript:output_file('$filename1','$trial')\"><br>";
	  print "<br><input type=\"button\" value=\"-\" onclick=\"javascript:output_file('$filename4','$trial')\"><br>";
      } else {
          print "<br><input type=\"button\" value=\"Error: no results from $chrom:$start-$stop\"><br>";
	  #print "$cmd\n";
      }
      if (-e $file_pas) {
        print "<br><input type=\"button\" value=\"Download Passport Data\" onclick=\"javascript:output_file('$file_pas','PassportData.xls')\">";
      }

    }
}

#$page->footer();