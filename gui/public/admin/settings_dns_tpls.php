<?php

/***********************************************************************************************************************
 * Functions
 */

function admin_getTemplates()
{
	$stmt = execute_query('SELECT dns_tpl_id, dns_tpl_name FROM dns_tpl');
	return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function admin_getTemplate()
{
	//$fileContent = file_get_contents('/etc/imscp/bind/parts/db.tpl');
}

/**
 * Create new DNS template version
 *
 * @param int $templateId
 * @param string $newTemplateName
 */
function admin_duplicateTemplate($templateId, $newTemplateName)
{
	if(!$templateId) {
		$stmt = execute_query(
			'
				INSERT INTO
					dns_tpl (dns_tpl_name, dns_tpl_content)
				SELECT
					?, dns_tpl_content
				FROM
					dns_tpl
				WHERE
					dns_tpl_id = ?
			',
			$templateId, $newTemplateName
		);

		if($stmt->rowCount()) {
			set_page_message('New DNS template version successfully created.', 'success');
		}
	}
}

function admin_editTemplate()
{

}

/**
 * Delete the given DNS template
 *
 * @param int $templateId Custom DNS template unique identifier
 * @return void
 */
function admin_deleteTemplate($templateId)
{
	$stmt = exec_query('SELECT dns_tpl_id FROM dns_tpl_admin LIMIT 1', $templateId);

	if($stmt->rowCount()) {
		set_page_message(tr('You cannot delete a DNS template already assigned to a reseller.', 'warning'));
	} else {
		$stmt = exec_query('DELETE FROM dns_tpl WHERE dns_tpl_id = ?', $templateId);

		if($stmt->rowCount()) {
			set_page_message('Custom DNS template successfully deleted.', 'success');
		} else {
			showBadRequestErrorPage();
		}
	}
}

/**
 * @param $tpl iMSCP_pTemplate
 */
function admin_generatePage($tpl)
{
	$templates = admin_getTemplates();

	array_unshift($templates, array('dns_tpl_id' => '0', 'dns_tpl_name' => 'i-MSCP'));

	foreach($templates as $template) {
		$tpl->assign(
			array(
				'TPL_ID' => $template['dns_tpl_id'],
				'TPL_NAME' => $template['dns_tpl_name']
			)
		);

		if(!$template['dns_tpl_id']) {
			$tpl->assign(
				array(
					'DNS_TPL_EDIT_LINK' => '',
					'DNS_TPL_DELETE_LINK' => ''
				)
			);
		} else {
			$tpl->parse('DNS_TPL_DELETE_LINK', 'dns_tpl_delete_link');
			$tpl->parse('DNS_TPL_EDIT_LINK', 'dns_tpl_edit_link');
		}


		$tpl->parse('DNS_TPL_BLOC', '.dns_tpl_bloc');
	}
}

/**
 * Check template name
 *
 * @param string $templateName Template name
 * @return void
 */
function admin_checkTempateName($templateName)
{
	if(preg_match('/^[a-z0-9]+$/', $templateName)) {
		$stmt = exec_query('SELECT dns_tpl_name FROM dns_tpl WHERE dns_tpl_name = ?', $templateName);
		if($stmt->rowCount()) {
			echo tr('Template name already in use.');
		} else {
			echo 'ok';
		}
	} else {
		echo tr('Wrong DNS template name.');
	}
}

/***********************************************************************************************************************
 * Main
 */

// Include core library
require 'imscp-lib.php';

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onAdminScriptStart);

check_login('admin');

$cfg = iMSCP_Registry::get('config');

if(isset($_REQUEST['action'])) {
	$action = clean_input($_REQUEST['action']);

	if($action == 'delete') {
		if(isset($_GET['id'])) {
			admin_deleteTemplate(clean_input($_GET['id']));
		} else {
			showBadRequestErrorPage();
		}
	} elseif($action == 'duplicate') {
		if(isset($_POST['id']) && isset($_POST['template_name'])) {
			admin_duplicateTemplate(clean_input($_POST['id']), clean_input($_POST['template_name']));
		} else {
			showBadRequestErrorPage();
		}
	} elseif($action == 'check') {
		admin_checkTempateName(clean_input($_POST['template_name']));
		exit;
	}
}


$tpl = new iMSCP_pTemplate();
$tpl->define_dynamic(
	array(
		'layout' => 'shared/layouts/ui.tpl',
		'page' => 'admin/settings_dns_tpls.tpl',
		'page_message' => 'layout',
		'dns_tpl_bloc' => 'page',
		'dns_tpl_edit_link' => 'dns_tpl_bloc',
		'dns_tpl_delete_link' => 'dns_tpl_bloc'
	)
);

$tpl->assign(
	array(
		'TR_PAGE_TITLE' => tr('Admin / Settings / DNS templates'),
		'ISP_LOGO' => layout_getUserLogo()));

generateNavigation($tpl);

$tpl->assign(
	array(
		'TR_DNS_INTERFACE_HINT' => tr('This interface allow you to manage your DNS templates.'),
		'TR_NAME' => tr('Name'),
		'TR_ACTIONS' => tr('Actions'),
		'TR_EDIT' => tr('Edit'),
		'TR_CREATE_NEW_VERSION' => tr('Create new version'),
		'TR_DELETE' => tr('Delete'),
		'TR_CREATE_NEW_TPL' => tr('Create new template'),
		'TR_UNIQUE_NAME_HINT' => tr('Please choose an unique name for the new template version.'),
		'DATATABLE_TRANSLATIONS' => getDataTablesPluginTranslations(),
		'TR_NEW_DNS_TEMPLATE_VERSION' => tr('New DNS template version'),
		'TR_DNS_TEMPLATE' => tr('DNS template'),
		'TR_TEMPLATE_NAME' => tr('Template name')
	)
);

admin_generatePage($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onAdminScriptEnd, array('templateEngine' => $tpl));

$tpl->prnt();

unsetMessages();
