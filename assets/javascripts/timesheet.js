$(function () {
  $('#select_timesheet_period_type_1').on('focus change', function () {
    $('#timesheet_period_type_1').prop('checked', true);
  });
  $('#timesheet-custom-period').on('click focusin change', function () {
    $('#timesheet_period_type_0').prop('checked', true);
  });
  $('#timesheet-form label.select-all').on('click', function (event) {
    event.preventDefault();
    var select = $(this).siblings('select');
    select.find('option').prop('selected', select.find(':selected').length !== select.find('option').length);
  });
  $('.timesheet-toggle').on('click', function (event) {
    event.preventDefault();
    var id = $(this).attr('data-timesheet-toggle');
    var expanded = $(this).attr('aria-expanded') !== 'true';
    $('[data-timesheet-details="' + id + '"]').prop('hidden', !expanded);
    $(this).attr('aria-expanded', String(expanded));
  });
  $('.timesheet-check-all').on('change', function () {
    $(this).closest('table').find('input[name="ids[]"]').prop('checked', this.checked).trigger('change');
  });
});
