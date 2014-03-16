define(['app/config/module'], function (module) {
	'use strict';

	module.factory('PanelService', ['$rootScope', '$location', '$anchorScroll', 'EventService', '$timeout', 'ArrayHelper', function ($rootScope, $location, $anchorScroll, eventService, $timeout, arrayHelper) {
		var panelService = arrayHelper([]);

		//

		panelService.toggleEnabled = function (item, state) {
			return panelService.toggle(item, 'enabled', state);
		};

		//

		panelService.toggleFold = function (item, state) {
			return panelService.echo(item, function (item) {
				if (!item.isFoldable())
					return undefined;

				return item.toggleFold(state);
			});
		};

		//

		panelService.focus = function (item) {
			return panelService.echo(item, function (item) {
				if (angular.isFunction(item.toggleFold))
					item.toggleFold(false);

				var $document = $(document),
					oldHeight = 0,
					newHeight = 0,
					rate = 100,
					timeout;

				var checkHeight = function () {
					newHeight = $document.innerHeight();

					if (oldHeight == newHeight) {
						$location.hash(item.id);
						$anchorScroll();
					} else {
						timeout = $timeout(function () {
							checkHeight();
						}, rate++);
						oldHeight = newHeight;
					}
				};

				checkHeight();

				return item;
			});
		};

		//

		panelService.refreshPanels = function () {
			angular.forEach(panelService, function (panel) {
				if (angular.isFunction(panel.refreshPanel))
					panel.refreshPanel();
			});
		};

		//

		$rootScope.$on('$routeChangeSuccess', function () {
			panelService.reset();
		});

		//

		return panelService;
	}]);
});
