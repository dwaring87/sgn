use strict;
use warnings;
use Test::More;
use Test::MockObject;

use lib 't/lib';
BEGIN { $ENV{SGN_SKIP_CGI} = 1 }
use SGN::Test 'ctx_request';
use SGN::Test::WWW::Mechanize;

BEGIN { use_ok 'SGN::View::Email::ErrorEmail' }

my $mech = SGN::Test::WWW::Mechanize->new;
$mech->with_test_level( process => sub {

    my ($res, $c) = ctx_request('/');
    $c->stash->{email_errors} = [ SGN::Exception->new( message => 'Fake test error!') ];
    my $email = $c->view('Email::ErrorEmail')->make_email( $c );

    is( $email->{subject}, '[SGN](E) /', 'got a good subject line' );
    like( $email->{body}, qr/object skipped/, 'email body looks right' );
    like( $email->{body}, qr/=== Request ===/, 'email body has a Request' );
    like( $email->{body}, qr/=== Summary ===/, 'email body has a Summary' );

});

done_testing();
