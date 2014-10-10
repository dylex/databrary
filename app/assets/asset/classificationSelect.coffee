'use strict'

app.directive 'classificationSelect', [
  'constantService',
  (constants) ->
    restrict: 'E'
    templateUrl: 'asset/classificationSelect.html'
    scope:
      value: '=ngModel'
      name: '@'
    link: ($scope) ->
      $scope.classification = constants.classification.slice(0)
      $scope.max = constants.classification.PUBLIC
      $scope.check = ($scope.value <= i for l, i in constants.classification)
      $scope.update = () ->
        $scope.value = $scope.check.indexOf(true)
]
