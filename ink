#!/usr/bin/python
# -*- coding: utf-8 -*-

import sys							# for argv
import os							# for directory creation
import shutil						# for directory deletion
import errno						# for mkdir_p()
import yaml							# for post metadata
import re							# for regexes
import fnmatch						# for wildcards
import PyRSS2Gen					# for generating RSS feed
import time							# for modification time
from markdown2 import markdown		# for conversion of Markdown to HTML
from smartypants import smartyPants	# for better typography
from datetime import datetime		# for adding current date to filename
from jinja2 import Environment, FileSystemLoader		# for templates
from subprocess import call			# for editing
from PIL import Image				# for preparing images
from inkconfig import inkconfig		# configuration

class Post:
	title = ''
	slug = ''
	date = ''
	content = ''
	template = ''

	year = ''
	month = ''
	day = ''
	filename = ''
	basename = ''

	# for baking existing posts (pass in something like "2011-03-25-blog-slug.text")
	def __init__(self, filename='', match=False):
		if filename != '':
			if match:
				filename = get_filename(filename)

			pattern = re.compile("(\d{4})-(\d{2})-(\d{2})-(.*).text")
			m = pattern.match(filename)

			self.year = int(m.groups()[0])
			self.month = int(m.groups()[1])
			self.day = int(m.groups()[2])
			self.filename = "%s.text" % m.groups()[3]
			self.basename = os.path.splitext(self.filename)[0]
			self.postfile = filename
			self.url = "blog/%04d/%02d/%s" % (self.year, self.month, self.basename)


	# publish a new post
	def publish(self, filename):
		# add current date to filename
		now = datetime.now()
		new_filename = "%04d-%02d-%02d-%s" % (now.year, now.month, now.day, filename)
		self.basename = os.path.splitext(filename)[0]

		# create posts/YEAR/DAY if it doesn't exist
		new_dir = "%s/posts/%04d/%02d" % (inkconfig["syspath"], now.year, now.month)
		mkdir_p(new_dir)

		# read in the file
		input = open(filename, 'r')
		lines = input.readlines()
		input.close()

		# prep
		frontmatter = lines[0].strip().split(' | ')
		self.title = frontmatter[0].strip()
		if len(frontmatter) > 1:
			self.categories = frontmatter[1].split(', ')
		else:
			self.categories = []

		self.content = lines[2:]					# skip blank line
		self.date = "%s %s, %s" % (now.strftime("%b"), now.day, now.year)
		self.year = now.year
		self.month = now.month
		self.day = now.day
		self.filename = "%s.text" % self.basename
		self.postfile = new_filename
		self.url = "blog/%04d/%02d/%s" % (self.year, self.month, self.basename)

		# create YAML frontmatter (date, title)
		metadata = yaml.dump({ 'title': self.title, 'date': self.date, 'categories': self.categories, 'template': 'post' }, default_flow_style = False)

		# parse it for images
		datestamp = '%04d/%02d' % (now.year, now.month)
		imagepath = '/images/%s' % datestamp
		imagelist = re.findall(r"\(\((.*)\)\)", ''.join(self.content))
		self.imagehtml = {}
		for image in imagelist:
			img = InkImage()
			image_metadata = image.split(' | ')
			img.filename = image_metadata[0]

			img.url = '%s/%s' % (imagepath, img.filename)
			img.classes = []

			# parse the string -- ex: ((test.jpg | 400 | floatright | url=http://google.com))
			for data in image_metadata[1:]:
				if data.isdigit():						# if it's a number, it's the width
					img.target_width = data
				else:
					if data.startswith('url='):			# it's a URL
						img.target_url = data[4:]
					elif data.startswith('alt='):		# it's alt text
						img.alt = data[4:]
					else:								# else it's a CSS class
						img.classes.append(data)

			# add CSS
			css = ' '.join(img.classes)
			if css != '':
				css = ' class="%s"' % css

			# and the alt text
			alt = img.alt.strip()

			# split it out 
			result = process_image(img.filename, datestamp, img.target_width)

			shadowbox = ''

			# if we've resized, use the thumbnail instead
			if result != '':
				if img.target_url == '':			# but don't override a URL if we've passed one in
					img.target_url = img.url
					shadowbox = ' rel="shadowbox"'
				img.url = "%s/%s" % (imagepath, result)

			if img.target_url != '':				# linked image
				self.imagehtml[img.filename] = '<figure%s><a href="%s"%s><img src="%s" alt="%s" /></a></figure>' % (css, img.target_url, shadowbox, img.url, alt)
			else:									# unlinked image
				self.imagehtml[img.filename] = '<figure%s><img src="%s" alt="%s" %s/></figure>' % (css, img.url, alt)

		# now go through again and replace the image tags
		new_content = []
		for line in self.content:
			line = re.sub(r"\(\((.*)\)\)", self.imagerepl, line)
			new_content.append(line)
		self.content = new_content

		# and save it to the new location
		output = open("%s/%s" % (new_dir, new_filename), 'w')
		output.write(metadata)
		output.write('----\n')
		for line in self.content:
			output.write(line)
		output.close()

		# bake
		self.bake(True)

		# update index.list
		index_list = "%s/posts/index.list" % inkconfig["syspath"]
		input = open(index_list, 'r')
		lines = input.readlines()
		input.close()

		if len(lines) > inkconfig["postsperpage"]:			# If there are too many posts on the home page, take the oldest one off
			lines.pop()
		lines.insert(0, '%s\n' % new_filename)

		output = open(index_list, 'w')
		output.write(''.join(lines))
		output.close()

		self.update(True)

		# bake index, RSS, archives page, sitemap
		site = Site()
		site.update()			

	# update category and monthly archive and, if necessary, the index
	def update(self, add):
		site = Site()

		# add to categories page and bake
		for category in self.categories:
			if add:
				site.add_to_category(category, self.postfile)
				print 'Added to category %s.' % category
			site.bake_category('%s.list' % get_category_slug(category))
			print 'Baked category %s.' % category

		# add to monthly archive page and bake
		if add:
			year, month = site.add_to_monthly_archive(self.postfile)
			print 'Added to monthly archive %02d/%s.' % (month, year)
		else:
			year, month = get_date_from_filename(self.postfile)
		site.bake_monthly_archive('%04d' % year, '%02d' % month)
		print 'Baked monthly archive %02d/%s.' % (month, year)

		# if we're rebaking, check index and if post is there, rebake index
		if not add:
			input = open('%s/posts/index.list' % inkconfig["syspath"], 'r')
			lines = input.readlines()
			input.close()

			if self.postfile in [line.strip() for line in lines]:
				site.bake_index()
				site.bake_rss()

		# add to sitemap if this is a new post, otherwise update sitemap
		if add:
			add_to_sitemap(self.url, 'post')
			print 'Added post to sitemap.'
		else:
			update_sitemap(self.url)
			print 'Updated post in sitemap.'

			site.bake_sitemap()


	# replace image tags
	def imagerepl(self, matchobj):
		imagestr = matchobj.group(1).split(' | ')
		return self.imagehtml[imagestr[0]]

	# load post
	def load(self, posttext, smarty=False):
		# separate YAML metadata out
		frontmatter = posttext.split('----')
		metadata = yaml.load(frontmatter[0])
		self.content = frontmatter[1]

		# parse metadata
		if smarty:
			self.title = smartyPants(metadata['title'])
		else:
			self.title = metadata['title']
		self.date = metadata['date']

		if metadata.has_key('template'):
			self.template = metadata['template']
		else:
			self.template = 'post'

		if metadata.has_key('categories'):
			self.categories = metadata['categories']
		else:
			self.categories = []

		# prepare category links
		categories = []
		for category in self.categories:
			url = '/blog/category/%s' % get_category_slug(category)
			categories.append("<a href='%s'>%s</a>" % (url, category))
		self.categoryhtml = ", ".join(categories)
	
		# and the description field
		self.desc = get_description(self.content)

		# convert from Markdown
		self.content = smartyPants(markdown(self.content))


	# bake post to HTML
	def bake(self, echo=False):
		dest_dir = "%s/web/blog/%04d/%02d" % (inkconfig["syspath"], self.year, self.month)
		mkdir_p(dest_dir)
		dest_file = "%s/%s.html" % (dest_dir, self.basename)

		# read file in
		input = open("%s/posts/%04d/%02d/%04d-%02d-%02d-%s.text" % (inkconfig["syspath"], self.year, self.month, self.year, self.month, self.day, self.basename), 'r')
		posttext = input.read()
		input.close()

		self.load(posttext, True)

		# now load any comments
		self.comments = load_comments("%s/posts/%04d/%02d/%04d-%02d-%02d-%s.comments" % (inkconfig["syspath"], self.year, self.month, self.year, self.month, self.day, self.basename))

		# prepare post slug (for comments system)
		post_slug = "%04d-%02d-%02d-%s" % (self.year, self.month, self.day, self.basename)

		# parse the breadcrumbs
		self.crumbs = []
		self.crumbs.append({ 'url': '/', 'title': 'Home' })
		self.crumbs.append({ 'url': '/archives', 'title': '%04d' % self.year })
		self.crumbs.append({ 'url': '/blog/%04d/%02d' % (self.year, self.month), 'title': '%02d' % self.month })
		
		# apply template
		env = Environment(loader=FileSystemLoader('%s/templates' % inkconfig["syspath"]))
		template = env.get_template('%s.html' % self.template)
		bakedhtml = template.render(title=self.title, date=self.date, desc=self.desc, categories=self.categoryhtml, comments=self.comments, content=self.content, post_slug=post_slug, breadcrumbs=self.crumbs, site_title=inkconfig["site_title"])

		# save HTML file to proper location
		output = open(dest_file, 'w')
		output.write(bakedhtml.encode('utf-8'))

		if echo:
			print "Baked post %s" % dest_file


class Page:
	title = ''
	slug = ''
	content = ''
	template = ''

	filename = ''
	basename = ''
	path = ''

	# for baking existing pages (pass in something like "slug.text")
	def __init__(self, filename='', match=False):
		if (filename != ''):
			if match:
				filename = get_filename(filename)

			self.filename = filename
			self.path, self.basename = os.path.split(self.filename)

	# bake a page
	def bake(self, filename=''):
		if (filename != ''):
			self.filename = filename
		self.path, self.basename = os.path.split(os.path.abspath(self.filename))

		# now get just the part after pages/
		self.relpath = self.path[self.path.find("pages")+6:]

		# get last modified date
		moddate = datetime.fromtimestamp(os.path.getmtime(self.filename))
		self.date = "%s %s, %s" % (moddate.strftime("%b"), moddate.day, moddate.year)

		# read the file in
		input = open(self.filename, 'r')
		pagetext = input.read()
		input.close()

		# separate YAML metadata out
		frontmatter = pagetext.split('----')
		metadata = yaml.load(frontmatter[0])
		self.content = frontmatter[1]

		# parse metadata
		self.title = smartyPants(metadata["title"])
		if metadata.has_key("template"):
			self.template = metadata["template"]
		else:
			self.template = "page"					# default
		if metadata.has_key("thumbnail"):
			self.thumbnail = metadata["thumbnail"]
		else:
			self.thumbnail = ''

		if metadata.has_key("breadcrumb"):
			breadcrumbs = '%s/' % metadata["breadcrumb"]
		else:
			# target URL
			base, ext = os.path.splitext(os.path.abspath(self.filename))
			target = base[base.find("pages")+6:]
			head, tail = os.path.split(target)

			if tail == 'index':
				tail = ''
			else:
				if head != '':
					tail = '/' + tail

			newbase = base[base.find("pages")+6:]
			breadcrumbs = '%s%s' % (head, tail)

		# parse the breadcrumbs
		self.crumbs = []
		if breadcrumbs:
			self.crumbs.append({ 'url': '/', 'title': 'Home' })
		
			for crumb in breadcrumbs.split('/')[:-1]:
				self.crumbs.append({ 'url': '/%s' % breadcrumbs[0:breadcrumbs.find(crumb)+len(crumb)], 'title': crumb })

		# and the description field
		self.desc = get_description(self.content)

		# Markdown and curly quotes
		self.content = smartyPants(markdown(self.content))

		# apply template
		env = Environment(loader=FileSystemLoader('%s/templates' % inkconfig["syspath"]))
		template = env.get_template('%s.html' % self.template)
		bakedhtml = template.render(title=self.title, date=self.date, desc=self.desc, content=self.content, thumbnail=self.thumbnail, breadcrumbs=self.crumbs, metadata=metadata, site_title=inkconfig["site_title"])

		# prep the directory
		if self.relpath != '':
			dest_dir = '%s/web/%s' % (inkconfig["syspath"], self.relpath)
		else:
			dest_dir = '%s/web' % inkconfig["syspath"]
			self.relpath = ''
		mkdir_p(dest_dir)

		# save the HTML file
		dest_file = '%s/%s.html' % (dest_dir, os.path.splitext(self.basename)[0])
		output = open(dest_file, 'w')
		output.write(bakedhtml.encode('utf-8'))

		print "Baked page %s" % (dest_file)

		# update sitemap
		basename = os.path.splitext(self.basename)[0]

		if self.relpath != '':
			url = '%s/%s' % (self.relpath, basename)
		else:
			url = basename

		update_sitemap(url)
		print 'Updated page in sitemap.'

		site = Site()
		site.bake_sitemap()



class Comment:
	author = ''
	author_url = ''
	date = ''
	content = ''

	def parse(self, comment):
		authordata = comment[0][8:].split(" || ")	# everything after "|"
		self.author = authordata[0]

		if len(authordata) > 1:
			self.author_url = authordata[1].strip()
		if len(authordata) > 2 and authordata[2] == "*":
			self.authcomment = True

		if self.author_url:
			if not self.author_url.startswith('http://'):
				self.author_url = 'http://%s' % self.author_url
			self.author_display = "<a href='%s'>%s</a>" % (self.author_url, self.author)
		else:
			self.author_display = self.author

		self.author_display = self.author_display.decode('utf-8')
		self.email = comment[1][6:]
		self.date = comment[2][6:]
		self.content = ('\n').join(comment[3:])
		self.content = smartyPants(markdown(self.content))

	def approve(self, filename):
		# read file
		input = open(filename, 'r')
		lines = input.readlines()
		input.close()

		# first line is link to blog post
		postfile = lines[0].strip()

		# parse comment
		comment = lines[2:]

		# get directory
		year, month = get_date_from_filename('%s.text' % postfile)

		# load comments for blog file
		commentsfile = '%s/posts/%04d/%02d/%s.comments' % (inkconfig["syspath"], year, month, postfile)

		if os.path.exists(commentsfile):
			# we've already gotten comments on this one
			output = open(commentsfile, 'a')
			output.write('----\n')
		else:
			# no comments yet
			output = open(commentsfile, 'w')

		output.write('%s' % ''.join(comment))
		output.close()

		# bake the parent post
		post = Post('%s.text' % postfile)
		post.bake(True)


class Site:
	def update(self):
		self.bake_index()
		self.bake_rss()
		self.bake_archives()
		self.bake_sitemap()

	def bake_index(self):
		input = open('%s/posts/index.list' % inkconfig["syspath"], 'r')
		lines = input.readlines()
		input.close()

		bake_page_list(lines, 'index', 'Home', 'index.html', 1, 1, inkconfig["postsperpage"])
		print "Baked index."

	def bake_rss(self):
		# bake RSS for main site
		bake_rss_feed('%s/posts/index.list' % inkconfig["syspath"], '%s/web/feed.xml' % inkconfig["syspath"], inkconfig["site_title"], inkconfig["site_desc"], False, False)
		print "Baked RSS."

	def bake_posts(self):
		pattern = re.compile("(\d{4})-(\d{2})-(\d{2})-(.*)\.text")

		for root, dirs, files in os.walk('%s/posts' % inkconfig["syspath"]):
			for name in files:
				if pattern.match(name):
					post = Post(name)
					post.bake(True)

	def bake_pages(self):
		pattern = re.compile("(.*).text")

		for root, dirs, files in os.walk('%s/pages' % inkconfig["syspath"]):
			for name in files:
				if pattern.match(name):
					page = Page(os.path.join(root, name))
					page.bake()

	def bake_categories(self):
		for root, dirs, files in os.walk('%s/posts/category' % inkconfig["syspath"]):
			for name in files:
				print "Baking category %s" % name
				self.bake_category(name)

	def bake_category(self, catfile):
		# read file in
		input = open("%s/posts/category/%s" % (inkconfig["syspath"], catfile), 'r')
		cattext = input.read()
		input.close()

		dest_dir = "blog/category/%s" % os.path.splitext(catfile)[0]
		dest_dir_abs = '%s/web/%s' % (inkconfig["syspath"], dest_dir)

		# if category directory exists, wipe it out
		if os.path.exists(dest_dir_abs):
			shutil.rmtree(dest_dir_abs)

		# create category directory
		mkdir_p(dest_dir_abs)

		# separate YAML metadata out
		frontmatter = cattext.split('----\n')
		metadata = yaml.load(frontmatter[0])
		catlist = frontmatter[1].strip()

		# read in title
		title = metadata["title"]

		# paginate with chunks
		catlist = catlist.split('\n')
		catlist.reverse()
		pages = list(chunks(catlist, inkconfig["postsperpage"]))

		num_posts = len(catlist)
		num_pages = len(pages)

		# for each page in the chunked list
		counter = 1
		for page in pages:
			if counter == 1:
				filename = 'index.html'
				pagetitle = ''
			else:
				filename = 'page%d.html' % counter
				pagetitle = ', Page %d' % counter

			# bake it like index to page[n+1].html
			bake_page_list(page, 'category', 'Archive: %s%s' % (title, pagetitle), '%s/%s' % (dest_dir, filename), counter, num_pages, num_posts, True)

			counter += 1

		# and now bake the RSS feed for it
		bake_rss_feed('%s/posts/category/%s' % (inkconfig["syspath"], catfile), '%s/web/%s/feed.rss' % (inkconfig["syspath"], dest_dir), '%s: %s' % (inkconfig["site_title"], title), 'Category feed')


	def bake_monthly_archive(self, year, month):
		# read file in
		input = open("%s/posts/%s/%s/index.list" % (inkconfig["syspath"], year, month), 'r')
		lines = input.readlines()
		input.close()

		# paginate with chunks
		lines.reverse()
		pages = list(chunks(lines, inkconfig["postsperpage"]))

		num_posts = len(lines)
		num_pages = len(pages)

		dest_dir = 'blog/%s/%s' % (year, month)

		# Prep display names
		month_names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
		name = '%s %s' % (month_names[int(month) - 1], year)

		# for each page in the chunked list
		counter = 1
		for page in pages:
			if counter == 1:
				filename = 'index.html'
				pagename = ''
			else:
				filename = 'page%d.html' % counter
				pagename = ', Page %d' % counter

			# bake it like index to page[n+1].html
			bake_page_list(page, 'archive', 'Archive: %s%s' % (name, pagename), '%s/%s' % (dest_dir, filename), counter, num_pages, num_posts, True)

			counter += 1

	def bake_monthly_archives(self):
		month_names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

		# Go through each blog/\4d/\2d directory, read index.list, translate month to name and put count
		years = os.listdir('%s/posts' % inkconfig["syspath"])
		for year in years:
			if year.isdigit():
				months = os.listdir('%s/posts/%s' % (inkconfig["syspath"], year))
				for month in months:
					if month.isdigit():
						print 'Baking %s/%s' % (month, year)
						self.bake_monthly_archive(year, month)

	def bake_archives(self):
		# make sure the archives and category directories exist
		if not os.path.exists('%s/web/archives' % inkconfig["syspath"]):
			mkdir_p('%s/web/archives' % inkconfig["syspath"])
		if not os.path.exists('%s/posts/category' % inkconfig["syspath"]):
			mkdir_p('%s/posts/category' % inkconfig["syspath"])

		archives = []
		categories = []

		month_names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

		# Go through each blog/\4d/\2d directory, read index.list, translate month to name and put count
		years = os.listdir('%s/posts' % inkconfig["syspath"])
		for year in years:
			if year.isdigit():
				months = os.listdir('%s/posts/%s' % (inkconfig["syspath"], year))
				for month in months:
					if month.isdigit():
						input = open('%s/posts/%s/%s/index.list' % (inkconfig["syspath"], year, month), 'r')
						lines = input.readlines()
						input.close()

						name = '%s %s' % (month_names[int(month) - 1], year)

						archives.append({ 'name': name, 'url': '/blog/%s/%s' % (year, month), 'count': len(lines) })

		archives.reverse()

		# Go through each category/*.list, get title, count len(lines), output
		catfiles = os.listdir('%s/posts/category' % inkconfig["syspath"])
		for cat in catfiles:
			input = open('%s/posts/category/%s' % (inkconfig["syspath"], cat), 'r')
			cattext = input.read()
			input.close()

			# separate YAML metadata out
			frontmatter = cattext.split('----\n')
			metadata = yaml.load(frontmatter[0])
			catlist = frontmatter[1].strip()

			# read in title
			name = metadata["title"]
			slug = os.path.splitext(cat)[0]

			# paginate with chunks
			lines = catlist.split('\n')

			categories.append({ 'name': name, 'url': '/blog/category/%s' % slug, 'count': len(lines) })

		# breadcrumbs
		self.crumbs = [{ 'url': '/', 'title': 'Home' }]

		# apply template
		env = Environment(loader=FileSystemLoader('%s/templates' % inkconfig["syspath"]))
		template = env.get_template('archives.html')
		bakedhtml = template.render(archives=archives, categories=categories, title='Archives', desc='Site archives', breadcrumbs=self.crumbs, site_title=inkconfig["site_title"])

		# save HTML file to proper location
		dest_file = '%s/web/archives/index.html' % inkconfig["syspath"]
		output = open(dest_file, 'w')
		output.write(bakedhtml.encode('utf-8'))

		print "Baked archives."

	def add_to_category(self, category, filename):
		slug = get_category_slug(category)
		catfile = '%s/posts/category/%s.list' % (inkconfig["syspath"], slug)

		if not os.path.exists('%s/posts/category' % inkconfig["syspath"]):
			mkdir_p('%s/posts/category' % inkconfig["syspath"])

		if os.path.exists(catfile):
			output = open(catfile, 'a')
		else:
			output = open(catfile, 'w')
			output.write('title: %s\n----\n' % category)
		output.write('%s\n' % filename)
		output.close()

	def add_to_monthly_archive(self, filename):
		year, month = get_date_from_filename(filename)

		archive = '%s/posts/%04d/%02d/index.list' % (inkconfig["syspath"], year, month)

		if os.path.exists(archive):
			output = open(archive, 'a')
		else:
			output = open(archive, 'w')
		output.write('%s\n' % filename)
		output.close()

		return (year, month)

	def bake_sitemap(self):
		input = open('%s/pages/sitemap.list' % inkconfig["syspath"], 'r')
		lines = input.readlines()
		input.close()

		output = open('%s/web/sitemap.xml' % inkconfig["syspath"], 'w')

		output.write('''<?xml version="1.0" encoding="UTF-8"?>\n''')
		output.write('''<!-- generator="ink" -->\n''')
		output.write('''<!-- generated-on="April 12, 2011 12:46 am" -->\n''')
		output.write('''<urlset xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd" xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n''')

		for line in lines:
			data = line.split(' | ')
			output.write('\t<url>\n')
			output.write('\t\t<loc>%s/%s</loc>\n' % (inkconfig["site_url"], data[0]))
			output.write('\t\t<lastmod>%s</lastmod>\n' % data[1])
			output.write('\t\t<changefreq>%s</changefreq>\n' % data[2])
			output.write('\t\t<priority>%s</priority>\n' % data[3].strip())
			output.write('\t</url>\n')

		output.write('</urlset>')
		output.close()

		print 'Baked sitemap.'
	


class InkImage:
	filename = ''
	url = ''
	target_url = ''
	classes = []
	target_width = None
	alt = ''


def mkdir_p(path):
	try:
		os.makedirs(path)
	except OSError as exc:
		if exc.errno == errno.EEXIST:
			pass
		else: raise

def load_comments(filename):
	if os.path.exists(filename):
		input = open(filename, 'r')
		comments_text = input.read()
		input.close()

		comments = comments_text.split('----')
		c_array = []
		for comment in comments:
			comment = comment.strip().split('\n')

			c = Comment()
			c.parse(comment)
			c_array.append(c)
		
		return c_array
	return []

def is_post(filename):
	path = os.path.abspath(filename)

	if path.find('%s/posts' % inkconfig["syspath"]) != -1:
		return True
	return False

def is_page(filename):
	path = os.path.abspath(filename)

	if path.find('%s/pages' % inkconfig["syspath"]) != -1:
		return True
	return False

def get_filename(filename):
	# checks for filename and if it doesn't exist, does wildcard completion

	if (filename != ''):
		if os.path.exists(filename):
			return filename
		else:
			# check fnmatch
			(path, basename) = os.path.split(filename)
			if path == '':
				path = '.'
			matches = fnmatch.filter(os.listdir(path), '*%s*.text' % basename)

			# if there's just one match, valid = True
			if len(matches) == 1:
				return matches[0]

			# otherwise throw an error
			elif len(matches) > 1:
				print "Too many possibilities:"
				for match in matches:
					print '  %s' % match
				sys.exit(-1)

			else:
				print "File not found"
				sys.exit(-1)

def process_image(filename, datestamp, targetwidth=None):
	img = Image.open(filename)
	(w, h) = img.size

	if targetwidth == None:
		targetwidth = inkconfig["imagewidth"]
	else:
		targetwidth = int(targetwidth)

	# destination
	dest_dir = "%s/web/images/%s" % (inkconfig["syspath"], datestamp)
	mkdir_p(dest_dir)

	# first save the original
	img.save("%s/%s" % (dest_dir, filename), quality=100)

	# now scale it down if we need to
	if w > targetwidth:
		targetheight = targetwidth * (float(h) / float(w))
		img.thumbnail((targetwidth, targetheight), Image.ANTIALIAS)
 
		(slug, extension) = os.path.splitext(filename)
		new_filename = '%s-%s%s' % (slug, targetwidth, extension)
		img.save('%s/%s' % (dest_dir, new_filename), quality=100)

		return new_filename

	return ''

def chunks(mylist, num_chunks):
	# not to be confused with nunchucks
	for i in xrange(0, len(mylist), num_chunks):
		yield mylist[i:i+num_chunks]

def add_to_sitemap(url, itemtype):
	if itemtype == 'post':
		frequency = 'daily'
		priority = '0.2'
	elif itemtype == 'page':
		frequency = 'weekly'
		priority = '0.6'

	output = open('%s/pages/sitemap.list' % inkconfig["syspath"], 'a')
	output.write('%s/ | %s | %s | %s\n' % (url, get_iso8601_date(), frequency, priority))
	output.close()

def update_sitemap(url):
	# read in the file
	input = open('%s/pages/sitemap.list' % inkconfig["syspath"], 'r')
	lines = input.read()
	input.close()

	url = re.sub(r'/index', r'', url)

	if re.match(r'^%s/ |' % url, lines):
		# find the url we want and replace the date with the new get_iso8601_date()
		lines = re.sub(r'%s/ \| [^|]*' % url, r'%s/ | %s ' % (url, get_iso8601_date()), lines)

		# save the file
		output = open('%s/pages/sitemap.list' % inkconfig["syspath"], 'w')
		output.write(lines)
		output.close()
	else:
		# add it to the sitemap
		if re.match(r'^blog/', url):
			itemtype = 'post'
		else:
			itemtype = 'page'
		add_to_sitemap(url, itemtype)

def get_category_slug(category):
	return category.lower().replace(".", "").replace("&amp;", "").replace(" ", "-")

def get_date_from_filename(filename):
	pattern = re.compile("(\d{4})-(\d{2})-(\d{2})-(.*).text")
	m = pattern.match(filename)

	year = int(m.groups()[0])
	month = int(m.groups()[1])

	return (year, month)

def get_iso8601_date():
	utcnow = datetime.utcnow()
	return '%s+00:00' % utcnow.replace(utcnow.year, utcnow.month, utcnow.day, utcnow.hour, utcnow.minute, utcnow.second, 0).isoformat()

def get_description(content):
	stripped = re.sub(r'#|_|<h[1-6]>|<\/h[1-6]>|<div.*?>|<\/div>|<a href=.*?<\/a>|\n>|\*|<i>|<\/i>|<b>|<\/b>|<img.*?>|<blockquote>|<\/blockquote>|<ul>|<\/ul>|<li>|</\li>|<p>|<\/p>', r'', content.decode('utf-8').strip())
	stripped = re.sub(r'’|‘|“|”|"|„', r"'", stripped)
	stripped = re.sub(r'\t|    |  ', r' ', stripped)
	stripped = re.sub(r'\n|    |  ', r'<br>', stripped)
	stripped = re.sub(r'\[(.*?)\]\(.*?\)', r'\1', stripped)
	stripped = re.sub(r'<br>(<br>)+', r"<br>", stripped)
	return '%s...' % stripped[0:250].strip()

def bake_page_list(lines, template_name, page_title, dest, cur_page, num_pages, num_posts, nav=False):
	# get posts and send to template
	posts = []
	for filename in lines:
		filename = filename.strip()
		post = Post(filename)

		# read file in
		input = open("%s/posts/%04d/%02d/%s" % (inkconfig["syspath"], int(post.year), int(post.month), filename), 'r')
		posttext = input.read()
		input.close()

		post.load(posttext, True)
		post.url = "/blog/%04d/%02d/%s" % (post.year, post.month, post.basename)
		posts.append(post)

	if nav:
		nav = []
		page_window = 5
		page_padding = 2

		if cur_page > 1 and num_pages > page_window:
			if (cur_page - 1) == 1:
				link = '.'
			else:
				link = './page%s' % (cur_page - 1)
			nav.append('<a rel="previous" href="%s">&laquo;&nbsp;Prev</a>' % link)

		# figure out our range
		x = cur_page - page_padding
		y = cur_page + page_padding
		if x <= 1:
			x = 1
			y = page_window
		if y > num_pages:
			x = num_pages - page_window + 1
			if x < 1:
				x = 1
			y = num_pages
		
		for i in range(x, y + 1):
			if i == cur_page:
				nav.append('<span class="nav">%s</span>' % i)
			else:
				if i == 1:
					link = '.'
				else:
					link = './page%s' % i
				nav.append('<a class="nav" href="%s">%s</a>' % (link, i))
		
		if cur_page + page_padding < num_pages and num_pages > page_window:
			nav.append('<a rel="next" href="./page%s">Next&nbsp;&raquo;</a>' % (cur_page + 1))

		nav = '\n'.join(nav)
	else:
		nav = ''

	# parse the breadcrumbs and set up the RSS feed for categories
	crumbs = []
	rss = ''

	if template_name != 'index':
		crumbs.append({ 'url': '/', 'title': 'Home' })
		crumbs.append({ 'url': '/archives', 'title': 'Archives' })

		# target URL
		head, tail = os.path.split(dest[dest.find('blog')+5:])

		# drop the last part .html
			# category/lds
			# 2005/03
		# parse the breadcrumbs
		if head:
			if head[0:8] == 'category':
				for crumb in head.split('/')[1:]:
					crumbs.append({ 'url': '/blog/%s' % head[0:head.find(crumb)+len(crumb)], 'title': crumb })
				# the category slug is whatever's left after 'category/' in head
				rss = '/blog/category/%s/feed.rss' % head[9:]
			else:
				# monthly archive
				for crumb in head.split('/'):
					url = head[0:head.find(crumb)+len(crumb)]
					if len(url) == 4:
						url = '/archives'
					else:
						url = '/blog/%s' % url
					crumbs.append({ 'url': url, 'title': crumb })

	# apply template
	env = Environment(loader=FileSystemLoader('%s/templates' % inkconfig["syspath"]))
	template = env.get_template('%s.html' % template_name)
	bakedhtml = template.render(posts=posts, title=page_title, desc=page_title, cur_page=cur_page, num_pages=num_pages, num_posts=num_posts, nav=nav, breadcrumbs=crumbs, crumbtitle='Page %s' % cur_page, site_title=inkconfig["site_title"], rss=rss)

	# save HTML file to proper location
	dest_file = '%s/web/%s' % (inkconfig["syspath"], dest)
	output = open(dest_file, 'w')
	output.write(bakedhtml.encode('utf-8'))


def bake_rss_feed(inputfile, outputfile, title, desc, ignore=True, reverse=True):
	input = open(inputfile, 'r')
	lines = input.readlines()
	input.close()

	# ignore first two lines and only get up to the last ten
	if ignore:
		lines = lines[2:]
		lines = lines[-10:]
	
	# reverse list
	if reverse:
		lines.reverse()

	# get posts
	posts = []
	for filename in lines:
		filename = filename.strip()
		post = Post(filename)

		# read file in
		filepath = "%s/posts/%04d/%02d/%s" % (inkconfig["syspath"], post.year, post.month, filename)
		input = open(filepath, 'r')
		posttext = input.read()
		input.close()

		post.load(posttext, False)
		post.url = "%s/blog/%04d/%02d/%s" % (inkconfig["site_url"], post.year, post.month, post.basename)

		# get the mod time
		createtime = datetime.fromtimestamp(os.path.getmtime(filepath))
		posttime = time.strptime(post.date, '%b %d, %Y')
		postdatetime = datetime(posttime.tm_year, posttime.tm_mon, posttime.tm_mday, createtime.hour, createtime.minute, createtime.second)

		# replace relative URLs with absolute ones
		post.content = re.sub(r'''href=(['"])/''', r'href=\1%s/' % inkconfig["site_url"], post.content)
		post.content = re.sub(r'''src=(['"])/''', r'src=\1%s/' % inkconfig["site_url"], post.content)

		# generate the RSS
		item = PyRSS2Gen.RSSItem(
				title = post.title,
				link = post.url,
				description = post.content,
				guid = PyRSS2Gen.Guid(post.url),
				pubDate = postdatetime)
		posts.append(item)

	rss = PyRSS2Gen.RSS2(
			title = title,
			link = inkconfig["site_url"],
			description = desc,
			lastBuildDate = datetime.now(),
			items = posts)

	# save RSS file to proper location
	output = open(outputfile, 'w')
	output.write(rss.to_xml(encoding='utf-8'))


# MAIN STUFF

def process_args(action, target):
	if action == "post":					# publish a new post
		post = Post()
		post.publish(target)
	elif action == "edit":					# open external editor
		filename = get_filename(target)
		call([inkconfig["editor"], filename])	
		exit(-1)
	elif action == "deploy":				# deploy via rsync
		call(["rsync", "-av", "--delete", "-e ssh", "%s/" % inkconfig["syspath"], "%s" % inkconfig["site_target"]])
	elif action == "status":				# check what would be deployed
		call(["rsync", "-avn", "--delete", "-e ssh", "%s/" % inkconfig["syspath"], "%s" % inkconfig["site_target"]])
	elif action == "bake":
		if target == 'index':				# bake the home page
			site = Site()
			site.bake_index()
		elif target == 'rss':					# posts
			site = Site()
			site.bake_rss()
		elif target == 'posts':					# posts
			site = Site()
			site.bake_posts()
		elif target == 'pages':
			site = Site()
			site.bake_pages()
		elif target == 'categories':
			site = Site()
			site.bake_categories()
		elif target == 'monthly':
			site = Site()
			site.bake_monthly_archives()
		elif target == 'archives':
			site = Site()
			site.bake_archives()
		elif target == 'sitemap':
			site = Site()
			site.bake_sitemap()
		elif target == 'all':
			site = Site()
			site.bake_posts()
			site.bake_pages()
			site.bake_index()
			site.bake_rss()
			site.bake_categories()
			site.bake_monthly_archives()
			site.bake_archives()
			site.bake_sitemap()
		else:
			if is_post(target):				# bake an existing post
				post = Post(target, True)
				post.bake(True)
				post.update(False)
			elif is_page(target):			# bake a page
				page = Page(target, True)
				page.bake()
	elif action == "approve":
		c = Comment()
		c.approve(target)

def main():
	if len(sys.argv) > 1:
		action = sys.argv[1]
		target = ''
		if len(sys.argv) > 2:
			target = sys.argv[2]
		process_args(action, target)
	else:
		print "Usage: ink [post|bake|edit] FILENAME"

if __name__ == "__main__":
	main()
