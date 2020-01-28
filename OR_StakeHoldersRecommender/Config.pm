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



use constant NAME => 'OR_StakeHoldersRecommender';

use constant REQUIRED_MODULES => [
    {
        package => 'Data-Dumper', 
        module => 'Data::Dumper', 
        version => 0,
    },
    {
        package => 'LWP-UserAgent', 
        module => 'LWP::UserAgent', 
        version => 2.18,
    },
    {
        package => 'Encode', 
        module => 'Encode', 
        version => 2.88,
    },
    {
        package => 'HTTP-Request', 
        module => 'HTTP::Request', 
        version => 6.14,
    },
    {
        package => 'JSON-MaybeXS', 
        module => 'JSON::MaybeXS', 
        version => 1.003009,
    },
    {
        package => 'JSON', 
        module => 'JSON', 
        version => 4.02,
    },
    {
        package => 'JSON-PP', 
        module => 'JSON::PP', 
        version => 2.27,
    },
];



use constant OPTIONAL_MODULES => [

];



__PACKAGE__->NAME;