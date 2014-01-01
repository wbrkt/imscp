<p class="hint" style="font-variant: small-caps;font-size: small;">
	{TR_DNS_INTERFACE_HINT}
</p>

<table class="datatable">
	<thead>
	<tr>
		<th>{TR_NAME}</th>
		<th>{TR_ACTIONS}</th>
	</tr>
	</thead>
	<tbody>
	<!-- BDP: dns_tpl_bloc -->
	<tr>
		<td>{TPL_NAME}</td>
		<td>
			<span class="icon i_open clickable" data-id="{TPL_ID}">{TR_CREATE_NEW_VERSION}</span>
			<!-- BDP: dns_tpl_edit_link -->
			<span class="icon i_edit clickable" data-id="{TPL_ID}">{TR_EDIT}</span>
			<!-- EDP: dns_tpl_edit_link -->
			<!-- BDP: dns_tpl_delete_link -->
			<a class="icon i_close clickable" href="settings_dns_tpls.php?action=delete&id={TPL_ID}">{TR_DELETE}</a>
			<!-- EDP: dns_tpl_delete_link -->
		</td>
	</tr>
	<!-- EDP: dns_tpl_bloc -->
	</tbody>
</table>

<div id="dialog-form1" title="{TR_NEW_DNS_TEMPLATE_VERSION}">
	<p class="hint" style="font-variant: small-caps;font-size: small;">
		{TR_UNIQUE_NAME_HINT}
	</p>
	<p class="validateTips">All form fields are required.</p>
	<form action="settings_dns_tpls.php" method="post">
		<table>
			<tr>
				<td><label for="template_name">{TR_TEMPLATE_NAME}</label></td>
				<td><input type="text" name="template_name" id="template_name" /></td>
			</tr>
		</table>

		<input name="id" type="hidden" value="" />
	</form>
</div>

<div id="dialog-form2" title="Edit DNS template">
	<form>
		<div id="status"></div>
		<table>
			<thead>
			<tr>
				<th>{TR_DNS_TEMPLATE}</th>
			</tr>
			</thead>
			<tbody>
			<tr>
				<td><label><textarea id="dns_tpl_content"></textarea></label></td>
			</tr>
			</tbody>
		</table>
	</form>
</div>

<script>
	$(function() {

		var templateName = $("#template_name"),
			allFields = $([]).add(templateName),
			tips = $(".validateTips");

		function updateTips(t) {
			//tips.text(t).addClass("ui-state-highlight");
			tips.text(t).addClass("error message");
			//setTimeout(function() { tips.removeClass("ui-state-highlight", 1500 ); }, 500 );
		}

		function checkLength(o, n, min, max ) {
			if (o.val().length > max || o.val().length < min) {
				o.addClass( "ui-state-error" );
				updateTips("Length of " + n + " must be between " + min + " and " + max + "." );
				return false;
			} else {
				return true;
			}
		}

		function checkRegexp( o, regexp, n ) {
			if ( !( regexp.test( o.val() ) ) ) {
				o.addClass("ui-state-error");
				updateTips( n );
				return false;
			} else {
				return true;
			}
		}

		$( "#dialog-form1" ).dialog({
			hide: "blind",
			show: "slide",
			autoOpen: false,
			height: 'auto',
			width: 650,
			modal: true,
			buttons: {
				"Create": function() {
					alert('god');
					var bValid = true;
					allFields.removeClass("ui-state-error");
					bValid = bValid && checkLength(templateName, "template name", 3, 16);
					bValid = bValid && checkRegexp(
						templateName,
						/^[a-z]([0-9a-z_])+$/i,
						"Template name may consist of a-z, 0-9, underscores, begin with a letter."
					);

					$.ajax({
						type: "POST",
						url: "settings_dns_tpls.php",
						data: "action=check&template_name=" + templateName,
						success: function(msg) {
							alert(msg);
						}
					});







					if (bValid) {
						$( this ).dialog( "close" );
					}
				},
				"Cancel": function() { $(this).dialog("close"); }
			},
			close: function() {
				allFields.val( "" ).removeClass( "ui-state-error" );
			}
		});


		$(".datatable").dataTable({ "oLanguage":{DATATABLE_TRANSLATIONS}, "bStateSave": true});













		$( "#dialog-form2" ).dialog({
			hide: "blind",
			show: "slide",
			autoOpen: false,
			height: 'auto',
			width: 650,
			modal: true,
			buttons: {
				"Ok": function() { },
				"Cancel": function() { $(this).dialog("close"); }
			}
		});

		$(".i_open").click(function() { $( "#dialog-form1" ).dialog( "open" ); } );
		$(".i_edit").click(function() { $( "#dialog-form2" ).dialog( "open" ); } );


		/*$("#template_name").change(function() {
			tplName = $(this).val();
			$.ajax({
				type: "POST",
				url: "settings_dns_tpls.php",
				data: "action=check&template_name=" + tplName,
				success: function(msg) {
					alert(msg);
				}
			});
		});*/

	});
</script>
