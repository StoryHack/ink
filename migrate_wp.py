#!/usr/bin/python

# quick Python script to slurp the posts and comments out of a WordPress installation and prep them for Ink
#
# Note: this doesn't slurp pages

import MySQLdb, os, errno, yaml

class Comment:
	author = ''
	author_email = ''
	author_url = ''
	date = ''
	content = ''
	me = False

class Post:
	title = ''
	slug = ''
	date = ''
	content = ''
	id = -1
	guid = ''

	categories = []
	comments = []

	def load_categories(self, db):
		self.categories = []
		db.execute("SELECT wp_terms.name FROM wp_terms INNER JOIN wp_term_taxonomy ON wp_terms.term_id = wp_term_taxonomy.term_id INNER JOIN wp_term_relationships ON wp_term_relationships.term_taxonomy_id = wp_term_taxonomy.term_taxonomy_id WHERE wp_term_relationships.object_id = %s AND taxonomy = 'category' ORDER BY wp_terms.name;" % (self.id))
		rows = db.fetchall()

		for row in rows:
			if (row[0] != "Uncategorized"):
				self.categories.append(row[0])

	def load_comments(self, db):
		db.execute("SELECT comment_author, comment_author_email, comment_author_url, comment_date, comment_content, user_id FROM wp_comments WHERE comment_post_ID = %s AND comment_approved = 1 ORDER BY comment_date ASC;" % (self.id))
		rows = db.fetchall()

		self.comments = []
		for row in rows:
			comment = Comment()
			comment.author = row[0]
			comment.author_email = row[1]
			comment.author_url = row[2]
			comment.date = row[3]
			comment.display_date = "%s %s, %04d at %s:%02d %s" % (comment.date.strftime("%b"), comment.date.strftime("%d").lstrip('0'), comment.date.year, comment.date.strftime("%I").lstrip('0'), comment.date.minute, comment.date.strftime("%p").lower())
			comment.content = row[4].strip().replace('\r', '')
			if (row[5] == 2):	# my user ID is 2
				comment.me = True
			self.comments.append(comment)


	def save(self):
		display_date = "%s %s, %s" % (self.date.strftime("%b"), self.date.day, self.date.year)
		filename = "%04d-%02d-%02d-%s.text" % (self.date.year, self.date.month, self.date.day, self.slug)
		comments_filename = "%04d-%02d-%02d-%s.comments" % (self.date.year, self.date.month, self.date.day, self.slug)
		dest_dir = "posts/%04d/%02d" % (self.date.year, self.date.month)

		mkdir_p(dest_dir)

		metadata = yaml.dump({ 'title': self.title, 'date': display_date, 'template': 'post', 'id': int(self.id), 'guid': self.guid, 'categories': self.categories }, default_flow_style = False)

		output = open("%s/%s" % (dest_dir, filename), 'w')
		output.write(metadata)
		output.write('----\n')
		output.write(self.content)
		output.close()

		print "Saved %s to %s/%s" % (self.slug, dest_dir, filename)

		if (len(self.comments) > 0):
			count = 0
			output = open("%s/%s" % (dest_dir, comments_filename), 'w')
			for comment in self.comments:
				if count > 0:
					output.write('\n----\n')

				output.write('author: %s' % comment.author)

				if comment.author_url != '':
					output.write(' || %s' % comment.author_url)

				if comment.me:
					output.write(' || *')

				output.write('\n')
				output.write('email: %s\n' % comment.author_email)
				output.write('date: %s\n' % comment.display_date)

				output.write('\n')
				output.write(comment.content)

				count += 1

			output.close()

			print "\tSaved %d comments to %s/%s" % (count, dest_dir, comments_filename)

		# save to archive
		archive_list = 'posts/%04d/%02d/index.list' % (self.date.year, self.date.month)
		if os.path.exists(archive_list):
			mode = 'a'
		else:
			mode = 'w'
		output = open(archive_list, mode)
		output.write('%s\n' % filename)
		output.close()

		print "\tSaved to archive %s" % archive_list

	def save_categories(self):
		mkdir_p('posts/category')

		for category in self.categories:
			# URLify the category name
			catname = category.lower().replace(".", "").replace("&amp;", "").replace(" ", "-")
			dest_file = "posts/category/%s.list" % catname
			post_file = "%04d-%02d-%02d-%s.text" % (self.date.year, self.date.month, self.date.day, self.slug)

			if os.path.exists(dest_file):
				mode = 'a'
			else:
				mode = 'w'

			output = open(dest_file, mode)

			# if we're starting the file, put the title in
			if mode == 'w':
				output.write('title: %s\n----\n' % category)

			output.write('%s\n' % post_file)
			output.close()

			print "\tAdded %s to category %s" % (post_file, catname)


def mkdir_p(path):
	try:
		os.makedirs(path)
	except:
		pass

def dbconnect():
	try:
		conn = MySQLdb.connect(host = 'localhost', user = 'DBUSERNAME', passwd = 'DBPASSWORD', db = 'DBNAME')
		return (conn, conn.cursor())
	except MySQLdb.Error, e:
		return "Error %d: %s" % (e.args[0], e.args[1])

def dbclose(conn, cursor):
	cursor.close()
	conn.commit()
	conn.close()

def migrate():
	(conn, db) = dbconnect()

	db.execute("SELECT post_title, post_name, post_date, post_content, ID, guid from wp_posts where post_status = 'publish' and post_type = 'post'")
	rows = db.fetchall()

	posts = []
	for row in rows:
		post = Post()
		post.title = row[0]
		post.slug = row[1]
		post.date = row[2]
		post.content = row[3].strip().replace('\r', '')
		post.id = row[4]
		post.guid = row[5]
		posts.append(post)

	for post in posts:
		post.load_categories(db)
		post.load_comments(db)
		post.save()
		post.save_categories()
	

	dbclose(conn, db)

migrate()
