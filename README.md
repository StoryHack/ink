# Ink

Ink is a static blog engine and CMS written in Python, using Markdown/YAML for pages and posts and jinja2 for templates. Everything's run on the command line. You bake everything locally and then deploy to production (using rsync on the backend). Licensed under the MIT license.


## Dependencies

* [python-markdown2](http://github.com/trentm/python-markdown2) for Markdown
* [smartypants.py](http://web.chad.org/projects/smartypants.py/) for typographer's quotes
* [jinja2](http://jinja.pocoo.org/) for templating
* [PyRSS2Gen](http://www.dalkescientific.com/Python/PyRSS2Gen.html) for RSS feed generation
* [PyYAML](http://pyyaml.org/) for post/page metadata
* [PIL](http://www.pythonware.com/products/pil/) for resizing images
* [jQuery](http://www.jquery.com/)


## Installation

1. Download the files or clone the repository to your local box.
2. Download the latest version of jQuery and put it in `web/js/jquery.js`
3. Install python-markdown2, jinja2, PyRSS2Gen, PyYAML, and PIL following the instructions on their sites. If you're on a Mac, you'll need to install Xcode to get the Python includes needed to install PIL.
4. To install smartypants.py, put `smartypants.py` somewhere in your `PYTHONPATH` (on my Mac, it's `/usr/lib/python2.7`)
5. Put the Ink directory in your `$PATH`.
6. Copy `inkconfig.sample.py` to `inkconfig.py`.


## Configuration

### inkconfig.py

Customize `inkconfig.py` for your site, using the following guide:

* `site_title`: shows up in the title element, in your RSS feed, etc.
* `site_url`: used for generating absolute URLs (for the RSS feed, etc.). Don't put a final slash on this.
* `site_desc`: description, used when generating the RSS feed.
* `site_target`: the filesystem destination for the site, using standard ssh syntax (e.g., `yoda@myblog.net:/srv/www/myblog.net`). You'll want ssh keys set up to do password-less sshing if you don't already have that set up. This target is what rsync uses as the destination when deploying the site.
* `syspath`: where your site resides on the local filesystem. This should be the absolute path to wherever you put Ink. (This way you can run Ink from anywhere and we don't have to worry about keeping relative paths straight.)
* `imagewidth`: the maximum width for images (they'll be scaled down automatically if they're larger than this).
* `editor`: for use in `ink edit`.
* `postperpage`: used on the home page and the archive/category pages.


### web/post_comments.php

Edit the `$EMAIL`, `$SITE`, and `$SITENAME` parts of `web/post_comments.php` (at the top of the file).


### Apache

Put the rules in the `htaccess` file either into a `.htaccess` file or your Apache config file for the site.

Also, you want the DocumentRoot on your site to point to the `web/` directory, not the Ink root. (If you did want it to be the Ink root, you'd have to add some rewrite rules to get everything to work.)

Here's kind of what it should look like (in your Apache config file):

	<VirtualHost YOUR.IP.ADDRESS:80>
		ServerAdmin youremail@gmail.com
		ServerName yourdomain.com
		DocumentRoot /path/to/ink/in/filesystem/web
	
		<Directory "/path/to/ink/in/filesystem/web">
			# The contents of the htaccess file go here

			Options FollowSymLinks -MultiViews
			AllowOverride All
			Order allow,deny
			Allow from all

			# etc.
		</Directory>
	</VirtualHost>


### Templates

Edit the files in the `templates/` directory to your liking. Here's where each template file is used:

* `archive.html`: for monthly archive pages (use `ink bake monthly` to bake)
* `archives.html`: for the archives page (use `ink bake archives` to bake)
* `category.html`: for the category archive pages (use `ink bake categories` to bake)
* `footer.html`: included by every page
* `header.html`: also included by every page
* `index.html`: for the home page
* `page.html`: for static pages in `pages/`
* `post.html`: for blog posts

And you can read the [Jinja2 documentation](http://jinja.pocoo.org/docs/) to learn how to use the templating system. (It's pretty easy, though.)

The default template points to `web/css/style.css` and `web/css/mobile.css` for CSS.


## Usage

### Posting

First off, the filename for each post should look like this: `slug-for-post.text` (obviously changing the slug to whatever you want the slug to be). The contents look like this:

	Jabberwocky | Poetry, Random

	'Twas brillig, and the slithy toves  
	  Did gyre and gimble in the wabe:  
	All mimsy were the borogoves,  
	  And the mome raths outgrabe.  

	((jabberwocky.png))

	((lewis-carroll.jpg | 150 | floatright | alt=Lewis Carroll's face | url=http://en.wikipedia.org/wiki/Lewis_Carroll))

	### More about the poem

	Lorem ipsum etc.

So, title goes on the first line, followed by a pipe and then a comma-separated list of categories. After a blank line, the body of the post is normal Markdown, with one exception: to have Ink upload images, use the double parentheses syntax explained below. (You can also use normal HTML/Markdown image tags to reference images elsewhere on the web, of course.)

Once you've got your post written, type `ink post jabberwocky.text`.

Ink will copy your post to the appropriate location (something like `posts/2011/06/2011-06-01-jabberwocky.text`), add it to the list of posts on the home page, add it to the appropriate monthly archive page and any category pages you've specified, and bake all those pages as well as the RSS feed. It will also find any images you've included (see below for more detail on the syntax), resize them if necessary, and copy them into the appropriate location (`web/images/2011/06/jabberwocky.png` and `web/images/2011/06/lewis-carroll.jpg`, in this case).

Note: I recommend using relative links in your posts when linking to other content on your site. If you do, Ink will bake them into absolute links when generating the RSS feed.

#### Image syntax

The parameters in the image line can be in any order as long as the image filename comes first. Separate parameters with pipes.

* Numbers (the `150` in the example) are interpreted as being the target width for the image. You can use this to scale images down.
* To link the image to a URL, use `url=http://any/url/here`.
* To add alternate text, use `alt=My alternate text`.
* Anything else (such as `floatright`) will be added as a CSS class on the image.


### Adding pages

To add a page, create it in the `pages/` directory (and you can have subdirectories here as well) using the `slug.text` filename pattern and the following format for the contents:

	title: About
	----
	About me.

	### History

	Life story.

So, YAML metadata at the top (title is required), followed by a line with four hyphens, followed by the page content in Markdown.

Type `ink bake about.text` or just `ink bake about` (it'll look in the current directory for a filename matching that string) and Ink will bake the page into the appropriate location in the `web/` directory.

If you want to use a different template for a page (or a post), put the following line under `title` in your page file and put a corresponding template in your `templates/` directory:

	title: About
	template: book
	----
	etc.

(Which would load the template `book.html`.)


### Deploying

Type `ink deploy`. Ink will copy everything via rsync to your destination. (By default Ink copies everything over, including your `pages/` and `posts/` directories, so you have an automatic backup.)

If you want to see what'll be deployed before you actually deploy, type `ink status`.

Also, Ink syncs the destination directory to exactly match your local directory. If you want any files on the destination, they need to be in your local `web/` directory. (Files that are on the destination but not in the local directory get deleted.)


### Editing/baking existing posts/pages

To edit posts, go to the `posts/` directory and find the post you want to edit. You can open the file with any editor, but if you want to make things a little easier, you can type something like `ink edit jabberwocky`, which will look in the current directory for a filename matching the string `jabberwocky` and then open it in whatever editor you've set in `inkconfig.py`.

To edit pages, go to the `pages/` directory and edit the file. The `ink edit [partial-filename]` trick works here, too. (It works anywhere, actually.)

After you've edited the page or the post, going along with our previous Jabberwocky post example, just type `ink bake jabberwocky` (or part of the filename, just like with `ink edit`) and Ink will bake the HTML to the appropriate location.


### Moderating comments

When someone leaves a comment, Ink emails it to you as an attachment. Save the attachment somewhere and, in the directory where you've saved it, type `ink approve comment.text`. It'll add the comment to that post and then bake the post.


### Baking

You can use the following commands to bake various parts of the site:

* `ink bake all` -- everything
* `ink bake posts` -- all the posts
* `ink bake pages` -- everything in the `pages/` directory
* `ink bake categories` -- the category pages
* `ink bake monthly` -- the monthly archives pages
* `ink bake archives` -- the archives page
* `ink bake index` -- the home page
* `ink bake rss` -- the RSS feed
* `ink bake sitemap` -- the sitemap.xml file
