<?php

$EMAIL = "youremailhere";
$SITE = "http://yoursiteurl.com";
$SITENAME = "Your Site Name";

// get POST data
$author = $_POST["author"];
$email = $_POST["email"];
$url = $_POST["url"];
$comment = $_POST["comment"];

$nonce = $_POST["nonce"];
$humpty = $_POST["humpty"];

$post_slug = $_POST["post_slug"];

$post_url_data = preg_match('/(\d\d\d\d)-(\d\d)-\d\d-(.*)/', $post_slug, $matches);
$post_url = "$SITE/blog/{$matches[1]}/{$matches[2]}/{$matches[3]}#comments";

// do some minimal spam prevention
if ($nonce == "31415926" && ($humpty == "" || $humpty == $email)) {
	// create attachment
	$mime_boundary = "<<<--==+X[" . md5(time()) . "]";

	$headers = "From: Ink <$EMAIL>" . "\r\n";
	$headers .= "X-Mailer: PHP/" . phpversion();
	$headers .= "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: multipart/mixed; boundary=\"" . $mime_boundary . "\"";

	$message .= "This is a multi-part message in MIME format.\r\n--$mime_boundary\r\n";
	$message .= "Content-Type: text/plain; charset=\"iso-8859-1\"\r\n";
	$message .= "Content-Transfer-Encoding: 7bit\r\n\r\n";

	// create the comment attachment
	$attach = $post_slug;
	$attach .= "\n----\n";
	$attach .= "author: $author";
	if ($url) { $attach .= " || $url"; }
	$attach .= "\nemail: $email";
	$attach .= "\ndate: " . date("M j, Y") . " at " . date("g:i a") . "\n";
	$attach .= $comment;

	// and the email
	$message .= "New comment on $post_url\n\n";

	$message .= "Author: " . stripslashes($author) . "\n";
	$message .= "Email: " . stripslashes($email) . "\n";
	$message .= "URL: " . stripslashes($url) . "\n";
	$message .= "Date: " . date("M j, Y") . " at " . date("g:i a") . "\n\n";

	$message .= stripslashes($comment) . "\n";

	// attach the file
	$filename = "comment.text";

	$message .= "--$mime_boundary\r\n";
	$message .= "Content-Type: application/octet-stream; name=\"$filename\"\r\n";
	$message .= "Content-Transfer-Encoding: base64\r\n";
	$message .= "Content-Disposition: attachment; filename=\"$filename\"\r\n\r\n";
	$message .= chunk_split(base64_encode($attach));
	$message .= "\r\n\r\n--$mime_boundary--\r\n";

	$subject = "[$SITENAME] Comment: $author ($post_slug)";

	// send it to admin
	$status = mail($EMAIL, $subject, $message, $headers);
	if ($status) {
		$status = 1;
	} else {
		$status = 0;
	}
} else {
	$status = -1;
}

echo json_encode(array("statuscode" => $status));

?>
