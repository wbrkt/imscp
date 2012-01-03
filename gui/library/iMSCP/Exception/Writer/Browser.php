<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 *
 * The contents of this file are subject to the Mozilla Public License
 * Version 1.1 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * The Original Code is "ispCP - ISP Control Panel".
 *
 * The Initial Developer of the Original Code is ispCP Team.
 * Portions created by Initial Developer are Copyright (C) 2006-2010 by
 * isp Control Panel. All Rights Reserved.
 *
 * Portions created by the i-MSCP Team are Copyright (C) 2010-2011 by
 * i-MSCP a internet Multi Server Control Panel. All Rights Reserved.
 *
 * @category	i-MSCP
 * @package		iMSCP_Exception
 * @subpackage	Writer
 * @copyright	2006-2010 by ispCP | http://isp-control.net
 * @copyright	2010-2012 by i-MSCP | http://i-mscp.net
 * @author		Laurent Declercq <l.declercq@nuxwin.com>
 * @link		http://i-mscp.net i-MSCP Home Site
 * @license		http://www.mozilla.org/MPL/ MPL 1.1
 */

/** @see iMSCP_Exception_Writer */
require_once  'iMSCP/Exception/Writer.php';

/**
 * Browser writer class
 *
 * This writer writes an exception messages to the client browser. This writer acts also as a formatter that will use a
 * specific template for the message formatting. If no template path is given, or if the template file is not reachable,
 * a string that represent the message is write to the client browser.
 *
 * The given template should be a template file that can be treated by a
 * pTemplate object.
 *
 * @category	i-MSCP
 * @package		iMSCP_Exception
 * @subpackage	Writer
 * @author		Laurent Declercq <l.declercq@nuxwin.com>
 * @version		0.0.3
 */
class iMSCP_Exception_Writer_Browser extends iMSCP_Exception_Writer
{
	/**
	 * pTemplate instance
	 *
	 * @var iMSCP_pTemplate
	 */
	protected $_tpl;

	/**
	 * Template file path
	 *
	 * @var string
	 */
	protected $_templateFile;

	/**
	 * Constructor.
	 *
	 * @param string $templateFile Template file path
	 */
	public function __construct($templateFile = '')
	{
		$this->_templateFile = (string)$templateFile;
	}

	/**
	 * Writes the exception message to the client browser.
	 *
	 * @return void
	 */
	protected function _write()
	{
		if (!($tpl = $this->_tpl)) {
			$tpl = new iMSCP_pTemplate();
			$tpl->define_no_file(
				'layout',
				'
					<html>
						<head>
							<title>i-MSCP - internet Multi Server Control Panel - Exception</title>
						</head>
						<body>
							<h1>{BOX_MESSAGE_TITLE}</h1>
							<p>{BOX_MESSAGE}</p>
						</body>
					</html>
				');

			$tpl->assign(
				array(
					'BOX_MESSAGE_TITLE' => 'An exception has been thrown.',
					'BOX_MESSAGE' => $this->_message));
		}

		$tpl->parse('LAYOUT', 'layout');

		iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onExceptionToBrowserEnd, new iMSCP_Events_Response($tpl));
		$tpl->prnt();
	}

	/**
	 * This methods is called from the subject.
	 *
	 * @param SplSubject $exceptionHandler iMSCP_Exception_Handler
	 * @return void
	 */
	public function update(SplSubject $exceptionHandler)
	{
		iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onExceptionToBrowserStart);

		/** @var $exceptionHandler iMSCP_Exception_Handler */
		// Always write the real exception message if we are the admin
		if (isset($_SESSION) &&
			((isset($_SESSION['logged_from']) && $_SESSION['logged_from'] == 'admin')
				|| isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'admin')
		) {
			$this->_message = $exceptionHandler->getException()->getMessage();
		} else {
			$productionException = $exceptionHandler->getProductionException();

			// An exception for production exists ? If it's not case, use the
			// real exception raised
			$this->_message = ($productionException)
				? $productionException->getMessage()
				: $exceptionHandler->getException()->getMessage();
		}

		if ($this->_templateFile) {
			$this->_render();
		}

		// Finally, we write the output
		$this->_write();
	}

	/**
	 * Render exception template file.
	 *
	 * @return void
	 */
	protected function _render()
	{
		$tpl = new iMSCP_pTemplate();
		$tpl->define_dynamic(
			array(
				'layout' => 'shared/layouts/simple.tpl',
				'page' => $this->_templateFile,
				'page_message' => 'layout',
				'backlink_block' => 'page'));

		if (iMSCP_Registry::isRegistered('backButtonDestination')) {
			$backButtonDestination = iMSCP_Registry::get('backButtonDestination');
		} else {
			$backButtonDestination = 'javascript:history.go(-1)';
		}

		$tpl->assign(
			array(
				'TR_PAGE_TITLE' => 'i-MSCP - internet Multi Server Control Panel - Exception',
				'CONTEXT_CLASS' => 'box_message',
				'productLink' => 'http://www.i-mscp.net',
				'productLongName' => 'internet Multi Server Control Panel',
				'productCopyright' => '© 2010-2011 i-MSCP Team<br/>All Rights Reserved',
				'THEME_COLOR_PATH' => '/themes/' . 'default',
				'BOX_MESSAGE_TITLE' => 'An exception have been thrown',
				'PAGE_MESSAGE' => '',
				'BOX_MESSAGE' => $this->_message,
				'THEME_CHARSET' => 'UTF-8',
				'BACK_BUTTON_DESTINATION' => $backButtonDestination,
				'TR_BACK' => 'Back'));

		$tpl->parse('LAYOUT_CONTENT', 'page');

		$this->_tpl = $tpl;
	}
}
