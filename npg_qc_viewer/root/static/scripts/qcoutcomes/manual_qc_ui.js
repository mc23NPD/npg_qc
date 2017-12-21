/*
* Copyright (C) 2015 Genome Research Ltd.
*
* This file is part of NPG software.
*
* NPG is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
/* globals $: false, define: false */
"use strict";
define([
  'jquery',
  './qc_utils'
], function (
  jquery,
  qc_utils
) {
var NPG;
/**
 * @module NPG
 */
(function (NPG) {
  /**
   * @module NPG/QC
   */
  (function (QC) {
    /**
     * @module NPG/QC/UI
     */
    (function(UI) {
      var MQCOutcomeRadio = (function() {
        /**
         * Widget to select the different outcomes of a lane. Internally
         * implemented as a radio.
         * @memberof module:NPG/QC/UI
         * @constructor
         * @param {String} id_pre - prefix for the id.
         * @param {String} outcome - outcome as string.
         * @param {String} label - HTML for the label of the radio (an image
         * for example).
         * @param {String} name - for the radio. Using the same name for
         * different radios groups them together.
         * @param {Object} checked - if checked is not undefined the radio
         * option will be marked as "checked" otherwise it will not be checked.
         * @author jmtc
         */
        MQCOutcomeRadio = function(id_pre, outcome, label, group, checked) {
          this.id_pre = id_pre;
          this.outcome = outcome;
          this.label = label;
          if (typeof (group) === "undefined" || group == null) {
            this.group = 'radios';
          } else {
            this.group = group;
          }
          if (typeof (checked) === "undefined" || checked == null) {
            this.checked = '';
          } else {
            this.checked = ' checked ';
          }
        };

        /**
         * Generates the HTML code of the radio and the label for this object.
         * @returns {String} HTML code representation.
         */
        MQCOutcomeRadio.prototype.asHtml = function() {
          var self = this;
          var internal_id = "radio_" + self.id_pre + "_" + self.outcome + "";
          var label = "<label for='" + internal_id + "'>" + self.label
              + "</label>";

          var html = "<input type='radio' id='" + internal_id + "' "
              + "name='" + self.group + "' value='" + self.outcome + "'"
              + self.checked + ">" + label;
          return html;
        };

        /**
         * Generates the HTML code of the radio and the label for this object, wraps
         * in JQuery object and returns
         * @returns {Object} JQuery object.
         */
        MQCOutcomeRadio.prototype.asObject = function() {
          var self = this;
          var obj = $(self.asHtml());
          return obj;
        };
        return MQCOutcomeRadio;
      })();
      UI.MQCOutcomeRadio = MQCOutcomeRadio;

      var MQCLibraryOverallControls = (function () {
        MQCLibraryOverallControls = function(abstractConfiguration, qcType) {
          this.PLACEHOLDER       = 'library_mqc_overall_controls';
          this.PLACEHOLDER_CLASS = '.' + this.PLACEHOLDER;

          this.abstractConfiguration = abstractConfiguration;

          this.CLASS_ALL_ACCEPT    = 'lane_mqc_accept_all';
          this.CLASS_ALL_REJECT    = 'lane_mqc_reject_all';
          this.CLASS_ALL_UNDECIDED = 'lane_mqc_undecided_all';
          //Title for the individual controls
          this.TITLE_ACCEPT    = 'Set all libraries in page as accepted';
          this.TITLE_REJECT    = 'Set all libraries in page as rejected';
          this.TITLE_UNDECIDED = 'Set all libraries in page as undecided';

          this.ICON_ACCEPT    = "<img src='" + abstractConfiguration.getRoot() + "/images/tick.png' width='10' height='10'/>";
          this.ICON_REJECT    = "<img src='" + abstractConfiguration.getRoot() + "/images/cross.png' width='10' height='10'/>";
          this.ICON_UNDECIDED = "<img src='" + abstractConfiguration.getRoot() + "/images/circle.png' width='10' height='10'/>";

          this.QC_TYPE = qcType;
        };

        MQCLibraryOverallControls.prototype.setupControls = function (placeholder) {
          placeholder = placeholder || $($(this.PLACEHOLDER_CLASS));
          //Remove the lane placeholder which will not be used in library manuql QC
          placeholder.parent().children('.lane_mqc_control').remove();
          placeholder.parent().append('<span class="lib_mqc_working"></span>');
          var accept = this.buildControl(this.CLASS_ALL_ACCEPT, this.TITLE_ACCEPT, this.ICON_ACCEPT);
          var und    = this.buildControl(this.CLASS_ALL_UNDECIDED, this.TITLE_UNDECIDED, this.ICON_UNDECIDED);
          var reject = this.buildControl(this.CLASS_ALL_REJECT, this.TITLE_REJECT, this.ICON_REJECT);
          placeholder.html(accept + und + reject);
          placeholder.parent().css('text-align', 'left');
          placeholder.css('padding-right', '5px').css('padding-left', '7px');
          $('.lane_mqc_overall').css('padding-left', '5px');
        };

        MQCLibraryOverallControls.prototype.buildControl = function (cssClass, title, representation) {
          var html = "<span class='lane_mqc_button lane_mqc_overall " + cssClass
                     + "' title='" + title
                     + "' >" + representation
                     + "</span>";
          return html;
        };

        MQCLibraryOverallControls.prototype.init = function (qcType) {
          var self = this;
          var all_accept = $($('.' + self.CLASS_ALL_ACCEPT).first());
          var all_reject = $($('.' + self.CLASS_ALL_REJECT).first());
          var all_und = $($('.' + self.CLASS_ALL_UNDECIDED).first());

          var placeholder = $($(self.PLACEHOLDER_CLASS));

          var requestUpdate = function (query, callback) {
            try {
              placeholder.parent()
                         .find('.lib_mqc_working')
                         .html("<img src='"
                               + self.abstractConfiguration.getRoot()
                               + "/images/waiting.gif' width='10' height='10' title='Processing request.'>");
              $.ajax({
                url: '/qcoutcomes',
                type: 'POST',
                contentType: 'application/json',
                data: JSON.stringify(query),
                cache: false
              }).error(function(jqXHR) {
                qc_utils.displayJqXHRError(jqXHR);
              }).success(function () {
                try {
                  qc_utils.removeErrorMessages();
                  callback();
                } catch (ex) {
                  qc_utils.displayError('Succesfully updated outcomes, but error while updating interface. ' + ex);
                }
              }).always(function() {
                placeholder.parent().find('.lib_mqc_working').empty();
              });
            } catch (ex) {
              qc_utils.displayError('Failed to update outcomes. ' + ex);
              placeholder.parent().find('.lib_mqc_working').empty();
            }
          };

          var resetOnClick = function () {
            var toReset = [all_accept, all_reject, all_und];
            for ( var i = 0; i < toReset.length; i++ ) {
              toReset[i].off('click').on('click', toReset[i].data('function_call'));
              toReset[i].css('background-color', '#F4F4F4');
            }
          };

          var prepareUpdate = function (outcome, caller, qcType) {
            try {
              var ids = [];
              $('.lane_mqc_control').closest('tr').each(function (index, element) {
                ids.push({rptKey: qc_utils.rptKeyFromId($(element).attr('id')), qc_outcome: outcome});
              });
              var outcomeType = 'lib' ;
              if (qcType === 'uqc') {
                outcomeType = 'uqc';
              }
              var query = qc_utils.buildUpdateQuery(outcomeType, ids);
              var callback = function () {
                resetOnClick();
                var new_outcome;
                $('.lane_mqc_control').each( function (index, element) {
                  var $element = $(element);
                  var controller = $element.data('gui_controller');
                  controller.updateView(outcome);
                  new_outcome = new_outcome || outcome;
                });
                $('.lane_mqc_control').closest('table').find('input:radio').val([new_outcome]);
                caller.css('background-color', '#D4D4D4');
                caller.off('click');
              };
              requestUpdate(query, callback);
            } catch (ex) {
              qc_utils.displayError('Error while preparing to update outcomes. ' + ex);
            }
          };

          var updateIfAllLibsSameOutcome = function () {
            try {
              var outcomes = [];
              var controlSelectorClass;
              if(self.QC_TYPE === 'mqc') {
                controlSelectorClass = '.lane_mqc_control';
              } else if (self.QC_TYPE === 'uqc'){
                controlSelectorClass = '.uqc_control';
              }
              $(controlSelectorClass).each( function (index, element) {
                outcomes.push($(element).data('gui_controller').outcome);
              });
              var unique = true;
              for ( var i = 0; i < outcomes.length; i++ ) {
                if ( outcomes[0] !== outcomes[i] ) { unique = false; break; }
              }
              resetOnClick();
              if ( unique ) {
                var button;
                switch ( outcomes[0] ) {
                  case qc_utils.OUTCOMES.ACCEPTED_PRELIMINARY: button = $('.' + self.CLASS_ALL_ACCEPT); break;
                  case qc_utils.OUTCOMES.REJECTED_PRELIMINARY: button = $('.' + self.CLASS_ALL_REJECT); break;
                  case qc_utils.OUTCOMES.ACCEPTED_UQC:         button = $('.' + self.CLASS_ALL_ACCEPT); break;
                  case qc_utils.OUTCOMES.REJECTED_UQC:         button = $('.' + self.CLASS_ALL_REJECT); break;
                  case qc_utils.OUTCOMES.UNDECIDED:            button = $('.' + self.CLASS_ALL_UNDECIDED); break;
                }
                if ( typeof button !== 'undefined') {
                  button.off('click');
                  button.css('background-color', '#D4D4D4');
                }
              }
            } catch (ex) {
              qc_utils.displayError('Error while updating interface, checking if all libraries have matching outcome. ' + ex);
            }
          };

          placeholder.data('updateIfAllMatch', updateIfAllLibsSameOutcome);

          all_accept.data('function_call', function () {
            var outcomeByQCType = qc_utils.selectOutcomeByQCType ('Accepted', qcType);
            prepareUpdate(outcomeByQCType, all_accept, qcType);
          });
          all_reject.data('function_call', function () {
            var outcomeByQCType = qc_utils.selectOutcomeByQCType ('Rejected', qcType);
            prepareUpdate(outcomeByQCType, all_reject, qcType);
          });
          all_und.data('function_call', function () {
            var outcomeByQCType = qc_utils.selectOutcomeByQCType ('Undecided', qcType);
            prepareUpdate(outcomeByQCType, all_und, qcType);
          });

          resetOnClick();
        };

        return MQCLibraryOverallControls;
      }) ();
      UI.MQCLibraryOverallControls = MQCLibraryOverallControls;

    })(NPG.QC.UI || (NPG.QC.UI = {}));
  }) (NPG.QC || (NPG.QC = {}));
}) (NPG || (NPG = {}));

return NPG;
});

