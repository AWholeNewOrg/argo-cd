package pull_request

import (
	"context"
	"fmt"

	"github.com/google/go-github/v35/github"

	gh "github.com/argoproj/argo-cd/v2/applicationset/services/internal/github"
)

type GithubService struct {
	client *github.Client
	owner  string
	repo   string
	labels []string
}

var _ PullRequestService = (*GithubService)(nil)

func NewGithubService(ctx context.Context, token, url, owner, repo string, labels []string) (PullRequestService, error) {
	client, err := gh.Client(ctx, &gh.ClientOptions{
		URL:   url,
		Token: token,
	})
	if err != nil {
		return nil, err
	}
	return &GithubService{
		client: client,
		owner:  owner,
		repo:   repo,
		labels: labels,
	}, nil
}

func (g *GithubService) List(ctx context.Context) ([]*PullRequest, error) {
	opts := &github.PullRequestListOptions{
		ListOptions: github.ListOptions{
			PerPage: 100,
		},
	}
	pullRequests := []*PullRequest{}
	for {
		pulls, resp, err := g.client.PullRequests.List(ctx, g.owner, g.repo, opts)
		if err != nil {
			return nil, fmt.Errorf("error listing pull requests for %s/%s: %w", g.owner, g.repo, err)
		}
		for _, pull := range pulls {
			if !containLabels(g.labels, pull.Labels) {
				continue
			}
			pullRequests = append(pullRequests, &PullRequest{
				Number:  *pull.Number,
				Branch:  *pull.Head.Ref,
				HeadSHA: *pull.Head.SHA,
			})
		}
		if resp.NextPage == 0 {
			break
		}
		opts.Page = resp.NextPage
	}
	return pullRequests, nil
}

// containLabels returns true if gotLabels contains expectedLabels
func containLabels(expectedLabels []string, gotLabels []*github.Label) bool {
	for _, expected := range expectedLabels {
		found := false
		for _, got := range gotLabels {
			if got.Name == nil {
				continue
			}
			if expected == *got.Name {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
