Micro.blog uses [IndieAuth](https://indieauth.net), which is a flavor of OAuth designed to work across web sites, not tied to a central authorization server. Because it’s based on OAuth, you can access Micro.blog from your app just like you would another OAuth provider.

You will mostly be accessing these URLs:

* authorization endpoint: `https://micro.blog/indieauth/auth`
* token endpoint: `https://micro.blog/indieauth/token`

### Authorization flow

To get started, open a web browser window from your app with the authorization endpoint, to ask the user to sign in to their Micro.blog account:

```
https://micro.blog/indieauth/auth?client_id=[url]&
  scope=create&
  state=[state]&
  response_type=code&
  redirect_uri=[url]
```

Note that Micro.blog does not have passwords, so this works best if the user is already signed in. For this reason, on mobile prefer opening the user’s default web browser (where they may already be signed in) rather than an embedded web view inside your app.

Parameters:

* `client_id`: This should be the URL for your app. It’s shown to users when prompted to sign in.
* `scope`: Set this to “create” so users can create new blog posts.
* `state`: This can be a random string that we’ll send back to you after authorization. You can verify that the value matches what you sent Micro.blog to prevent forged requests.
* `response_type`: Set this to “code”.
* `redirect_uri`: This is the callback URL that we’ll redirect back to.

When the user approves your app to access Micro.blog, we’ll redirect back to your `redirect_uri` with `state` and `code` values, like this:

```
https://yourapp.com/callback?state=12345&code=ABCDEFG
```

This redirect URL can also use a custom URL scheme:

```
yourapp://callback?state=12345&code=ABCDEFG
```

### Access tokens

With the authorization code, request an access token from Micro.blog's token endpoint by sending a `POST` to Micro.blog:

```
POST /indieauth/token
Host: micro.blog
Content-Type: application/x-www-form-urlencoded
Accept: application/json

code=ABCDEFG&client_id=https://yourapp.com&grant_type=authorization_code
```

Parameters:

* `code`: The code you were sent in the callback URL.
* `client_id`: This should be the URL for your app. It’s shown to users when prompted to sign in.
* `grant_type`: Set to “authorization\_code”.

Note that Micro.blog does not use a `client_secret` parameter like some OAuth providers need.

If everything works, you’ll get a JSON response with the acccess token to use in subsequent requests to the Micro.blog API:

```
{
  "access_token": "HIJKLMNOP",
  "token_type": "Bearer",
  "scope": "create",
  "me": "https://someone.micro.blog/",
  "profile": {
	"name": "Someone",
	"url": "https://someone.micro.blog/",
	"photo": "https://avatars.micro.blog/..."
  }
}
```

Send this token in the HTTP header “Authorization”, like this:

```
GET /posts/timeline
Host: micro.blog
Authorization: Bearer HIJKLMNOP
```

For a list of JSON endpoints you can use with a token, see this [help page](https://help.micro.blog/t/json-api/97).

### Client metadata

The `client_id` parameter is the URL that identifies your app. It can be the URL for your app's home page, or it can be a URL to a JSON file that describes the app in more detail. The following is a simple JSON file with fields that Micro.blog will use to show the user when approving your app:

```
{
  "client_name": "My App",
  "logo_uri": "https://myapp.example/logo.png"
}
```