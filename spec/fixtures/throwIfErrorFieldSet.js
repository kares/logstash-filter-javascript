
function filter(event) {
  var error = event.getField('error');
  if (error) throw new TypeError(error)
  event.setField('filtered', true)
}
