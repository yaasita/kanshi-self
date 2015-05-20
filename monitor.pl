#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Encode;
use MIME::Base64;

my $MAILTO_ALERT = 'huga@example.com';

{
    $ENV{LANG}="C";
    my $error = "";
    # メモリ
    my $free = `free -m`;
    chomp $free;
    $free =~ s/^/    /gm;
    if ($free =~ /buffers\/cache:\s+(\d+)\s+(\d+)/m and $2 == 0){
        $error .= "メモリが少なくなっています\n";
    }
    # Load Average
    my $w = `w | head -1 | perl -nle 'print \$& if /load average.*/'`;
    chomp $w;
    if ($w =~ /\s+(\d\.\d\d)$/ and $1 > 5){
        $error .= "負荷が高くなっています\n";
    }
    # ゾンビプロセス
    my $zombie = `ps aux | perl -nlae 'print \$F[7]' | grep -c Z`;
    chomp $zombie;
    if ($zombie > 0){
        $error .= "Zombieプロセスが存在します\n";
    }
    # ディスク使用量
    my $df  = `df -h /`;
    chomp $df;
    $df =~ s/^/    /gm;
    if ($df =~ /(\d+)%/ and $1 > 90){
        $error .= "ディスク使用量が90％を超えました\n";
    }
    # 監視プロセス
    my $ps_mysql   = system("pgrep mysqld > /dev/null") ? "NG" : "OK";
    my $ps_nginx   = system("pgrep nginx > /dev/null") ? "NG" : "OK";
    my $ps_unicorn = system("kill -0 \$(cat /home/ck_contest/rails/shared/tmp/pids/unicorn.pid 2> /dev/null) 2> /dev/null") ? "NG" : "OK";
    {
        my $check_ps = sub {
            my $ok_ng = shift;
            my $name = shift;
            if ($ok_ng eq "NG"){
                return "$name プロセスが動作していません\n";
            }
            else {
                return "";
            }
        };
        $error .= $check_ps->($ps_mysql,"mysql");
        $error .= $check_ps->($ps_nginx,"nginx");
        $error .= $check_ps->($ps_unicorn,"unicorn");
    }
    # 件名
    my $subject;
    if ($error eq ""){
        exit;
    }
    else {
        $subject = "【エラー】ほげ管理システム";
    }
    chomp $error;
    my $body = <<"EOS";
$error

* メモリ使用状況(単位Mbyte)
$free

* Load Average(1分, 5分, 15分の平均)
    $w

* Zombie プロセス数
    $zombie プロセス

* ディスク使用量
$df

* プロセス
    - nginx: $ps_nginx;
    - mysql: $ps_mysql;
    - unicorn: $ps_unicorn;
EOS
    sendmail($MAILTO_ALERT,$subject,$body);
}

sub sendmail {
    my $to = shift;
    my $subject = shift;
    my $body = shift;
    open (my $sendmailfh, "|-:encoding(UTF-8)", "/usr/sbin/sendmail -f $to $to") or die $!;
    print $sendmailfh &mail_heder($to,$subject);
    print $sendmailfh encode_base64(encode("UTF-8",$body));
    close $sendmailfh;
}
sub mail_heder {
    my $to = shift;
    my $subject = shift;
    my $date;
    {
        $ENV{'TZ'} = "JST-9";
        my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime(time);
        my @week = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat');
        my @month = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
        $date = sprintf("%s, %d %s %04d %02d:%02d:%02d +0900 (JST)", $week[$wday],$mday,$month[$mon],$year+1900,$hour,$min,$sec);
    } 
    my $mail_subject = `echo "$subject" | nkf -W -M -w`;
    chomp $mail_subject;
    my $message_id = time();
    my $head = <<"HEADER";
From: $to
To: $to
Content-Type: text/plain; charset=UTF-8
Message-Id: <$message_id>
Date: $date
Subject: $subject
Content-Transfer-Encoding: Base64
HEADER
    return $head;
}
