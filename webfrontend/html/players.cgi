#!/usr/bin/perl

use CGI;
use LoxBerry::System;
use HTML::Template;
use warnings;
use strict;

my $cgi = CGI->new;

# Template laden und JavaScript anhängen
my $template = LoxBerry::System::read_file("$lbptemplatedir/playermanager.html");
$template   .= LoxBerry::System::read_file("$lbptemplatedir/javascript.js");

my $templateout = HTML::Template->new_scalar_ref(
    \$template,
    global_vars       => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

# Sprachdatei
LoxBerry::System::readlanguage($templateout, "language.ini");

# ajax.cgi liegt im html-Verzeichnis (ohne Authentifizierung)
$templateout->param( AJAX_URL => "/plugins/$lbpplugindir/ajax.cgi" );

# Ausgabe: minimales HTML ohne LoxBerry-Header/-Footer
print "Content-Type: text/html; charset=utf-8\r\n\r\n";

print <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.5, maximum-scale=3, user-scalable=yes">
    <link rel="stylesheet" href="/system/scripts/jquery/themes/main/loxberry.css">
    <link rel="stylesheet" href="/system/scripts/jquery/jquery.mobile.structure-1.4.5.min.css">
    <script src="/system/scripts/jquery/jquery-1.12.4.min.js"></script>
    <script src="/system/scripts/jquery/jquery.mobile-1.4.5.min.js"></script>
    <script>
        $.mobile.ajaxEnabled = false;
        $.mobile.page.prototype.options.domCache = false;
        $(document).on("pagehide", "div[data-role=page]", function(event) {
            $(event.target).remove();
        });
        $.ajaxSetup({ cache: false });
        $.mobile.degradeInputs.range = false;
    </script>
    <style>
        body { margin: 0; padding: 0; background: #111; }
    </style>
</head>
<body>
HTML

print $templateout->output();

print <<'HTML';
</body>
</html>
HTML
