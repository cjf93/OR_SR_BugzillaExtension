# This Source Code Form is subject to the terms of the Mozilla Public

# License, v. 2.0. If a copy of the MPL was not distributed with this

# file, You can obtain one at http://mozilla.org/MPL/2.0/.

#

# This Source Code Form is "Incompatible With Secondary Licenses", as

# defined by the Mozilla Public License, v. 2.0.



package Bugzilla::Extension::OR_StakeHoldersRecommender;



use 5.10.1;

use strict;

use warnings;

use Data::Dumper;


use parent qw(Bugzilla::Extension);
use Bugzilla;
use Bugzilla::DB;
use Bugzilla::User;
use Bugzilla::Bug;

# External Libraries
use LWP::UserAgent();
use Encode qw(encode_utf8);
use HTTP::Request ();
use JSON::MaybeXS qw(encode_json);
use JSON;
use JSON::PP qw(decode_json);


# This code for this is in ../extensions/OR_StakeHoldersRecommender/lib/Util.pm

use Bugzilla::Extension::OR_StakeHoldersRecommender::Util;


my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my @days = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
our $VERSION = '0.01';

my $OR_SR_basePath = "http://94.23.216.167/upc/stakeholders-recommender/";

##### RECOMMEND PARAMETERS
my $OR_SR_k = 2;
my $OR_SR_organization = "UPC";
my $OR_SR_projectSpecific = "false";
##############

##### BATCH PROCESS PARAMS
my $OR_SR_autoMapping = "true";
my $OR_SR_keywordPreprocessing = "true";
my $OR_SR_keywords = "false";
my $OR_SR_logging = "false";
my $OR_SR_selectivityFactor ="4";
my $OR_SR_withAvailability = "false";
my $OR_SR_withComponent = "false";
############

my $cgi      = Bugzilla->cgi;
my $dbh  = Bugzilla->dbh;


sub install_update_db {
    ## This hook is performed after an installation or upgrade
    my ($self, $args) = @_;
    OR_SR_BatchProcess();
}

sub sanitycheck_check {
    ## It is common to have the sanitycheck.pl running nightly on a cronjob so the BatchProcess
    ## It's suitable to put it here
    my ($self, $args) = @_;
    OR_SR_BatchProcess();
}

sub template_before_process {
    my ($self, $args) = @_;

    my $config = $args->{'config'};
    my ($vars, $file) = @$args{qw(vars file)};

    my $template = Bugzilla->template;
    my $OR_SR_Bug_ProjectName;
    my $OR_SR_UserRequesting;
    my $OR_SR_Bug_ProjectID;
    my $OR_SR_Bug_ComponentID;
    my $OR_SR_Bug_ComponentName;
    my $OR_SR_Bug_ShortDesc;
    my $OR_SR_Bug_LastDiffed;

    my $OR_SR_Person_To_Assign;
    my $OR_SR_Debug_var = "0";

    my $id = $cgi->param('id');

    if ($file eq 'bug/edit.html.tmpl') {

        my $or_assign = $cgi->param('or_assign');
        if($or_assign){
            $OR_SR_Person_To_Assign = $or_assign;
           $vars->{'bug'}->set_assigned_to($OR_SR_Person_To_Assign);
        }

        my $or_k = $cgi->param('or_k');

        if(!$or_k) {
           $or_k = $OR_SR_k;
        }

        # Extract bug info
        $OR_SR_Bug_ProjectName = $vars->{'bug'}->{'product'};
        $OR_SR_UserRequesting = $vars->{'user'};
        $OR_SR_Bug_ProjectID = $vars->{'bug'}->product_id;
        $OR_SR_Bug_ComponentID = $vars->{'bug'}->component_id;
        $OR_SR_Bug_ComponentName = $vars->{'bug'}->component;
        $OR_SR_Bug_ShortDesc = $vars->{bug}->short_desc;
        $OR_SR_Bug_LastDiffed = $vars->{bug}->lastdiffed;

        my $newdate =  $OR_SR_Bug_LastDiffed;
        $newdate =~ s/ /T/;

        $OR_SR_Bug_LastDiffed = $newdate."Z";        

        # For now we use the admin as a user requesting.
        # Put your user before using for example $OR_SR_UserRequesting = "John.Doe\@email.com";
        $OR_SR_UserRequesting = "";

        my $header = ['Content-Type' => 'application/json;', 'accept' => '*/*'];
        my $data = "{ \"project\": {
            \"id\":\"".$OR_SR_Bug_ProjectID."\" },
            \"requirement\":{ \"description\": \"---\",
                \"effort\": \"3.0\",
                \"id\": \"".$id."\",
                \"modified_at\": \"".$OR_SR_Bug_LastDiffed."\",
                \"name\": \"".$OR_SR_Bug_ShortDesc."\",
                \"requirementParts\": [
                    {
                        \"id\": \"".$OR_SR_Bug_ComponentID."\",
                        \"name\": \"".$OR_SR_Bug_ComponentName."\"
                    }
                ]
            },
            \"user\": {
                \"username\": \"".$OR_SR_UserRequesting."\"
            }}";
        my $url = $OR_SR_basePath . "recommend?k=" . $or_k . "&organization=" . $OR_SR_organization . "&projectSpecific=" . $OR_SR_projectSpecific;

        my $r = HTTP::Request->new('POST',$url, $header, $data);
        my $ua = LWP::UserAgent->new;

        my $or_batch = $cgi->param('or_batch');
        my $responseDecoded = "";
        my $tojson;

        if($or_batch == 1) {
            OR_SR_BatchProcess();
        }
        elsif($or_batch == 0 || !$or_batch) {
            
            my $response = $ua->request($r);
            
            if ($response->is_success) {
                ## Save the result to a variable

                $responseDecoded = $response->decoded_content;
                $tojson   = decode_json($responseDecoded);
            }
            else {
                $OR_SR_Debug_var = $response->status_line;
            }
        }
            ## Push the variables to template
            $vars->{'OR_SR_RawJSON'}         = $responseDecoded;
            $vars->{'OR_SR_RecommendResponse'}         = $tojson;
            $vars->{'OR_SR_basePath'}         = $OR_SR_basePath;
            $vars->{'OR_SR_BugID'}         = $id;
            $vars->{'OR_SR_k'}         = $or_k;
            $vars->{'OR_SR_organization'}         = $OR_SR_organization;
            $vars->{'OR_SR_Error'} = $OR_SR_Debug_var;
        #}

    } 
}

sub OR_SR_BatchProcess {

    ############# EXECUTE SELECTS ########################
    my $dbh  = Bugzilla->dbh;

    my $sthPersons = $dbh->prepare(
    'SELECT bugs.profiles.login_name from bugs.profiles;') ;

    $sthPersons->execute();

    my $sthParticipants = $dbh->prepare(
    'SELECT bugs.bug_id, bugs.product_id, bugs.assigned_to, products.name, profiles.login_name from bugs.bugs 
    join bugs.products on bugs.bugs.product_id = bugs.products.id
    join bugs.profiles on bugs.bugs.assigned_to = bugs.profiles.userid
    WHERE bugs.assigned_to is not NULL;');

    $sthParticipants->execute();

    my $sthProjects = $dbh->prepare(
    'SELECT bugs.bugs.product_id, bugs.bugs.bug_id from bugs.bugs
    WHERE bugs.assigned_to is not NULL ORDER BY bugs.bugs.product_id;');

    $sthProjects->execute();

    my $sthResponsibles = $dbh->prepare(
    'SELECT bugs.bug_id, bugs.reporter, profiles.login_name from bugs.bugs 
    join bugs.profiles on bugs.bugs.reporter = bugs.profiles.userid
    WHERE bugs.assigned_to is not NULL;');

    $sthResponsibles->execute();

    my $sthRequirements = $dbh->prepare(
    'SELECT bugs.bugs.short_desc, bugs.bugs.bug_id, bugs.bugs.lastdiffed, bugs.bugs.component_id, bugs.components.name from bugs.bugs
    join bugs.components on bugs.bugs.component_id = bugs.components.id
    WHERE bugs.assigned_to is not NULL;');

    $sthRequirements->execute();

    ####################################
    my $JSON = JSON->new->utf8;
    $JSON->convert_blessed(1);

    my $jsonPersons;
    my $jsonParticipants;
    my $jsonProjects;
    my $jsonRequirements;
    my $jsonResponsibles;

    ## Persons
    my $rowPerson;
    my $Person;
    my @Persons;
    while($rowPerson = $sthPersons->fetchrow()) {
    $Person = new Person( $rowPerson);
    push @Persons, $Person;
    }
    my $jsonPersons = $JSON->encode(\@Persons);
    #####################################

    ## Participants
    my @rowParticipant;
    my $Participant;
    my @Participants;
    while(@rowParticipant = $sthParticipants->fetchrow_array()) {
    $Participant = new Participant(40, @rowParticipant[4], "".@rowParticipant[1]."");
    push @Participants, $Participant;
    }
    my $jsonParticipants = $JSON->encode(\@Participants);
    #####################################

    ## Projects
    my @rowProjects;
    my $Project;
    my @Projects;
    my $currentProdID = -1;
    my @currentBugsIDList = ();
    while(@rowProjects = $sthProjects->fetchrow_array()) {
    if($currentProdID == -1){
        $currentProdID = @rowProjects[0];
    }
    if($currentProdID != @rowProjects[0]){
        $Project = new Project($currentProdID, @currentBugsIDList);
        push @Projects, $Project;

        @currentBugsIDList = ();
        $currentProdID = @rowProjects[0];
        push @currentBugsIDList, @rowProjects[1];
    }
    else {
        push @currentBugsIDList, "".@rowProjects[1]."";
    }
    }
    $Project = new Project($currentProdID, @currentBugsIDList);
    push @Projects, $Project;

    my $jsonProjects = $JSON->encode(\@Projects);
    #####################################

    ## Requirements
    my @rowRequirement;
    my $Requirement;
    my @Requirements;
    my $RequirementsPart;
    while(@rowRequirement = $sthRequirements->fetchrow_array()) {
    #Change date from 2017-10-25 18:04:09Z to 2017-10-25T18:04:09Z
    my $newdate =  @rowRequirement[2];
    $newdate =~ s/ /T/;

    $RequirementsPart = new RequirementPart ("".@rowRequirement[3]."","".@rowRequirement[4]."");
    $Requirement = new Requirement("--", "3.0", "".@rowRequirement[1]."", $newdate."Z", @rowRequirement[0], $RequirementsPart);
    push @Requirements, $Requirement;
    }
    my $jsonRequirements = $JSON->encode(\@Requirements);
    #####################################

    ## Responsibles
    my @rowResponsible;
    my $Responsible;
    my @Responsibles;
    while(@rowResponsible = $sthResponsibles->fetchrow_array()) {
    $Responsible = new Responsible(@rowResponsible[2],"".@rowResponsible[0]."");
    push @Responsibles, $Responsible;
    }
    my $jsonResponsibles = $JSON->encode(\@Responsibles);
    #####################################

    ############# POST SR ########################
    my $header = ['Content-Type' => 'application/json;', 'accept' => '*/*'];
    my $data = "{ \"participants\":" . $jsonParticipants .", \n \"persons\": " . $jsonPersons .", \n \"projects\": " . $jsonProjects .", \n \"requirements\": " . $jsonRequirements .", \n \"responsibles\": " . $jsonResponsibles ."}";
    my $url = "http://localhost:9410/upc/stakeholders-recommender/batch_process?autoMapping=" . $OR_SR_autoMapping. "&keywordPreprocessing=". $OR_SR_keywordPreprocessing ."&keywords=". $OR_SR_keywords ."&logging=". $OR_SR_logging ."&organization=". $OR_SR_organization ."&selectivityFactor=". $OR_SR_selectivityFactor ."&withAvailability=". $OR_SR_withAvailability ."&withComponent=".$OR_SR_withComponent;

    #####################################
    ## Write to file BatchData
    #my $filename = '/tmp/SRBatchData.txt';
    #my $filename = '/tmp/testBZ.txt';
    #open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
    #print $fh "asd";

    #close $fh;
    #print length($jsonParticipants), "\n";
    #print length($jsonPersons), "\n";
    #print length($jsonProjects), "\n";
    #print length($jsonRequirements), "\n";
    #print length($jsonResponsibles), "\n";
    #####################################



    my $r = HTTP::Request->new('POST',$url, $header, $data);
    my $ua = LWP::UserAgent->new;
    $ua->request($r);
    #my $response = $ua->request($r);

    #if ($response->is_success) {
    #print STDERR $response->decoded_content;
    #}
    #else {
    #print STDERR "ERROR \n";
    #print STDERR $response->status_line, "\n";
    #}

    #####################################
    package Person;
    sub new {
    my $class = shift;
    my $self = {
        username => shift
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }

    package Participant;
    sub new {
    my $class = shift;
    my $self = {
        availability => shift,
        person => shift,
        project => shift
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }

    package Project;
    sub new {
    my $class = shift;
    my $self = {
        id => shift,
        specifiedRequirements => [ @_ ]
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }

    package Requirement;
    sub new {
    my $class = shift;
    my $self = {
        description => shift,
        effort => shift,
        id => shift,
        modified_at => shift,
        name => shift,
        requirementParts => [ @_ ]
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }

    package RequirementPart;
    sub new {
    my $class = shift;
    my $self = {
        id => shift,
        name => shift
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }

    package Responsible;
    sub new {
    my $class = shift;
    my $self = {
        person => shift,
        requirement => shift
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }

    package BatchProcessData;
    sub new {
    my $class = shift;
    my $self = {
        participants => shift,
        persons => shift,
        projects => shift,
        requirements => shift,
        responsibles => shift
    };

    bless $self, $class;
    return $self;
    }
    sub TO_JSON { return { %{ shift() } }; }
}



__PACKAGE__->NAME;