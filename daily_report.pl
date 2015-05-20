#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Encode;
use MIME::Base64;

my $MAILTO_REPORT = 'hoge@example.com';
my $TODAY = $ARGV[0] || &today;

sub today {
    use Time::Piece;
    my $t = localtime;
    return $t->strftime("%Y%m%d");
}

# メール送信
{
    $ENV{LANG}="C";
    # nginxアクセス数
    my $nginx = `bash -c 'grep \$(LANG=C date "+%d/%b/%Y") /var/log/nginx/access.log /var/log/nginx/access.log.1 | wc -l'`;
    chomp $nginx;
    # メモリ
    my $free = `free -m`;
    chomp $free;
    $free =~ s/^/    /gm;
    # Load Average
    my $w = `w | head -1 | perl -nle 'print \$& if /load average.*/'`;
    chomp $w;
    # ゾンビプロセス
    my $zombie = `ps aux | perl -nlae 'print \$F[7]' | grep -c Z`;
    chomp $zombie;
    # ディスク使用量
    my $df  = `df -h`;
    chomp $df;
    $df =~ s/^/    /gm;
    # 監視プロセス
    my $ps_mysql   = system("pgrep mysqld > /dev/null") ? "NG" : "OK";
    my $ps_nginx   = system("pgrep nginx > /dev/null") ? "NG" : "OK";
    my $ps_unicorn = system("kill -0 \$(cat /home/ck_contest/rails/shared/tmp/pids/unicorn.pid 2> /dev/null) 2> /dev/null") ? "NG" : "OK";
    # バックアップ確認
    my $backup;
    my $backup_file = `ls -1tr /mnt/daily/rails_backup* | tail -1`;
    chomp $backup_file;
    my $subject;
    if ($backup_file =~ /rails_backup_(\d+)/ and $1 eq $TODAY){
        $backup = "バックアップ: OK(最終バックアップファイル: $backup_file)";
        $subject = "【正常】ほげ管理システム日次報告";
    }
    else {
        $backup = "バックアップ: NG(最終バックアップファイル: $backup_file)";
        $subject = "【エラー】ほげ管理システム日次報告";
    }

    my $body = <<"EOS";
* nginxアクセス数
    $nginx request

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

* バックアップ
    $backup

EOS
    sendmail($MAILTO_REPORT,$subject,$body);
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
