$(document).ready(function() {
	// set up comment submission form
	$("#commentform input[type='submit']").click(function() {
		var author = $("#commentform #author").val();
		var email = $("#commentform #email").val();
		var url = $("#commentform #url").val();
		var comment = $("#commentform #comment").val();

		var nonce = $("#commentform #nonce").val();
		var humpty = $("#commentform #humpty").val();

		var post_slug = $("#commentform #post_slug").val();

		$("#spinner").show();

		$.post("/post_comment.php", { author: author, email: email, url: url, comment: comment, nonce: nonce, humpty: humpty, post_slug: post_slug }, function(data) {
			switch (data.statuscode) {
				case 1:
					$("#comment_submitted").fadeIn(125);
					$("#spinner").hide();
					break;
				case -1:
					// spam
					$("#spinner").hide();
					break;
				default:
					$("#comment_error").fadeIn(125);
					$("#spinner").hide();
					// didn't work
					break;
			}
		}, "json");

		return false;
	});
});
