use Bailador;
use URI::Escape;
use HTTP::Easy::PSGI;

sub git {
    chdir 'content';
    my $command = ('git', @_).map: "'" ~ *.subst("'", qq{'"'"'}) ~ "'";
    my $result = qqx{$command};
    print $result;
    chdir '..';
    $result;
}

Bailador::import;

my %file-types = <
    txt text/plain
    ico image/x-icon
    png image/png
    css text/css
>;

get /^\/RANDOM(\/.*)?$/ => sub ($page) {
    status 303;
    header "Location", '/' ~ dir('content').grep(/^ <-[.]>+ $/).pick ~ $page;
}

get /^\/(<-[./]><-[/]>*)\/edit\/?$/ => sub ($name is copy) {
    $name = uri_unescape $name;
    my $content = "";
    try { $content = slurp("content/$name") };
    template 'edit.tt', $name, $content;
}

post /^\/(<-[./]><-[/]>*)\/edit\/?$/ => sub ($name is copy) {
    $name = uri_unescape $name;
    spurt "content/$name", request.params<content>.subst: /\n?$/, "\n";
    git 'add', '.';
    git 'commit', '-m', request.params<reason> || 'No reason specified';
    status 303;
    header 'Location', "/$name";
    "";
}

get /^\/(<-[/]>*)[\/(<[0..9a..fA..F]>**5..*)]?\/?$/ => sub ($name is copy, $revision) {
    if "static/$name".IO.f {
        content_type %file-types{$name.split('.')[* - 1]};
        return slurp "static/$name";
    }
    $name = uri_unescape($name) || 'Main page';
    unless "content/$name".IO.f {
        status 404;
        return template '404.tt', $name;
    }
    my $content = $revision ?? git 'show', "$revision:$name" !! slurp "content/$name";
    if $content ~~ /'<<<<<<< HEAD'/ {
        status 303;
        header 'Location', "/$name/edit";
        return "";
    }
    if $revision {
        git 'checkout', 'master';
    }
    template 'index.tt', $name, $content;
}

get /^\/(<-[/]>*)\/log[\/(<[0..9a..fA..F]>**5..*)]?\/?$/ => sub ($name is copy, $from is copy) {
    $name = uri_unescape $name;
    my @log = git('log', "--pretty=%h\x01%s\x01%ar\x01%ai", '--', $name).lines.map: {[.split: "\x01"]};
    template 'log.tt', $name, $(@log), $from, $from ?? 'to revision' !! 'from revision';
}

get /^\/(<-[/]>*)\/log\/(<[0..9a..fA..F]>**5..*)\/(<[0..9a..fA..F]>**5..*)\/?$/ => sub ($name, $r1, $r2) {
    content_type 'text/plain';
    git 'diff', "$r1..$r2", '--',  uri_unescape $name;
}

get /^\/(<-[/]>*)\/revert\/(<[0..9a..fA..F]>**5..*)\/?$/ => sub ($name, $revision) {
    git 'revert', '-n', $revision;
    git 'commit', '-m', "Reverted $revision.";
    status 303;
    header "Location", "/$name";
}

baile;
