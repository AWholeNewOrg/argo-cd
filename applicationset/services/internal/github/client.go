package github

import (
	"context"
	"net/http"
	"os"

	"github.com/google/go-github/v35/github"
	"github.com/gregjones/httpcache"
	"golang.org/x/oauth2"
)

type contextKey struct{}

var cacheContextKey = contextKey{}

func ContextWithGithubCache(ctx context.Context, cache httpcache.Cache) context.Context {
	return context.WithValue(ctx, cacheContextKey, cache)
}

type ClientOptions struct {
	URL   string
	Token string
}

func Client(ctx context.Context, opts *ClientOptions) (*github.Client, error) {
	if opts == nil {
		opts = &ClientOptions{}
	}
	if cache, ok := ctx.Value(cacheContextKey).(httpcache.Cache); ok {
		ctx = context.WithValue(ctx, oauth2.HTTPClient, &http.Client{
			Transport: &httpcache.Transport{
				Cache: cache,
			},
		})
	}
	token := opts.Token
	// Undocumented environment variable to set a default token, to be used in testing to dodge anonymous rate limits.
	if token == "" {
		token = os.Getenv("GITHUB_TOKEN")
	}
	var ts oauth2.TokenSource
	if token != "" {
		ts = oauth2.StaticTokenSource(
			&oauth2.Token{AccessToken: token},
		)
	}
	httpClient := oauth2.NewClient(ctx, ts)
	if opts.URL == "" {
		return github.NewClient(httpClient), nil
	}
	return github.NewEnterpriseClient(opts.URL, opts.URL, httpClient)
}
