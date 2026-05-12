export const newCell = (initial) => () => ({ value: initial })

export const readCell = (cell) => () => cell.value

export const writeCell = (value) => (cell) => () => {
  cell.value = value
}
