package CPANRatings::Control::Rate;
use strict;
use base qw(CPANRatings::Control);
use POSIX qw(strftime);
use Combust::Constant qw(OK);

sub render {

    my $self = shift;

    my ($submit) = $self->request->uri =~ m!^/rate/submit!;

    my $template = 'rate/rate_form.html';

    $self->no_cache(1);

    return $self->login
      unless $self->is_logged_in;

    $self->tpl_param( 'user' => $self->user_info );

    $self->tpl_params->{module} = $self->req_param('module');

    my $distribution = $self->req_param('distribution');

    return $self->error('Distribution name required')
      unless $distribution;

    return $self->error( 'No such distribution: ' . $distribution )
      unless CPANRatings::Model::SearchCPAN->valid_distribution($distribution);

    $self->tpl_params->{distribution} = {
        name     => $distribution,
        releases => CPANRatings::Model::SearchCPAN->get_releases($distribution),
    };

    if ($submit) {
        my %errors;

        # TODO should check if the module is valid for the distribution

        my @fields =
          qw(rating_1 rating_2 rating_3 rating_4 rating_overall review version_reviewed module distribution);
        my %data;
        for my $f (@fields) {
            $data{$f} = $self->req_param($f);
            if ( $f =~ m/^rating_/ ) {
                $data{$f} = undef if defined $data{$f} and $data{$f} eq '';
            }
            else {
                $data{$f} //= '';
            }

            # warn "DATA: $f => [". (defined $data{$f} ? $data{$f} : 'undef') . "]";
            if ( grep { $f eq $_ } qw(distribution version_reviewed review) ) {
                $errors{$f} = "Required field"
                  unless defined $data{$f} and $data{$f} ne "";
            }
        }

        $data{user} = $self->user_info->id;

        unless (%errors) {

            $data{updated} = strftime "%Y-%m-%d %T", localtime
              unless $self->req_param('minor_edit');

            my $review;
            if (($review) = $self->schema->review->search(
                    {   distribution => $data{distribution},
                        user         => $data{user},
                    }
                )
              )
            {
                for my $f ( keys %data ) {
                    $review->$f( $data{$f} );
                }
                $review->update;

            }
            else {
                $review = $self->schema->review->create( \%data );
            }

            $self->tpl_param( 'review', $review );

            $template = 'rate/rate_submitted.html';
        }
        else {
            $self->setup_rate_form;
            $self->tpl_param( errors => \%errors );
        }
    }
    else {
        my ($review) = $self->schema->review->search(
            {   distribution => $distribution,
                user         => $self->user_info->id,
            }
        );

        if ($review) {
            $self->tpl_param( 'review', $review );
        }

        $self->setup_rate_form;
    }

    return OK, $self->evaluate_template($template);
}

sub setup_rate_form {
    my $self = shift;

    $self->tpl_params->{questions} = [
        {   field => 'rating_1',
            name  => 'Documentation'
        },
        {   field => 'rating_2',
            name  => 'Interface',
        },
        {   field => 'rating_3',
            name  => 'Ease of Use',
        },
        {   field => 'rating_overall',
            name  => 'Overall',
        },
    ];
}

sub error {
    my ( $self, $message ) = @_;

    $self->tpl_param( error => { message => $message } );
    $self->no_cache(1);
    return OK, $self->evaluate_template('rate/rate_error.html');
}


1;

__END__

